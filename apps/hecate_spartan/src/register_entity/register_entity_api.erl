%%% @doc Ingress: POST /v1/register.
%%%
%%% A self-sovereign entity proves it holds the private key behind its DID by
%%% signing the registration challenge; we verify, record entity_registered_v1,
%%% and return a freshly minted UCAN scoped to its realm topics. Re-registering
%%% (already a member) simply refreshes the UCAN.
%%%
%%% Request body (JSON):
%%%   { "entity_name": "...", "did": "did:key:...",
%%%     "pubkey": base64(32-byte ed25519 pubkey),
%%%     "signature": base64(sig over the registration challenge),
%%%     "ts": "<client timestamp string>" }
-module(register_entity_api).

-export([init/2, verify_registration/1]).

-dialyzer({nowarn_function, [do_register/3, reply_ucan/3]}).

init(Req0, State) ->
    case cowboy_req:method(Req0) of
        <<"POST">> -> handle_post(Req0, State);
        _          -> reply_json(405, #{error => method_not_allowed}, Req0, State)
    end.

handle_post(Req0, State) ->
    {ok, Body, Req1} = cowboy_req:read_body(Req0),
    case decode(Body) of
        {ok, Map} ->
            case verify_registration(Map) of
                {ok, Fields}    -> do_register(Fields, Req1, State);
                {error, Reason} -> reply_json(401, #{error => Reason}, Req1, State)
            end;
        {error, _} ->
            reply_json(400, #{error => invalid_json}, Req1, State)
    end.

do_register(#{did := Did} = F, Req, State) ->
    Cmd = register_entity_v1:new(maps:get(entity_name, F), Did,
                                 maps:get(pubkey, F), maps:get(registered_at, F)),
    case maybe_register_entity:dispatch(Cmd) of
        {ok, _V, _E}                 -> reply_ucan(Did, Req, State);
        {error, already_registered}  -> reply_ucan(Did, Req, State);
        {error, Reason} ->
            reply_json(500, #{error => dispatch_failed, reason => fmt(Reason)}, Req, State)
    end.

reply_ucan(Did, Req, State) ->
    Realm = realm(),
    case hecate_spartan_identity:mint_entity_ucan(Did, Realm) of
        {ok, Ucan} ->
            reply_json(200, #{did => Did,
                              ucan => Ucan,
                              service_did => hecate_spartan_identity:service_did(),
                              realm => Realm}, Req, State);
        {error, Reason} ->
            reply_json(500, #{error => mint_failed, reason => fmt(Reason)}, Req, State)
    end.

%% @doc Pure verification of a registration request map (binary keys, as
%% decoded from JSON). Checks presence, base64, pubkey length, and the
%% signature over the challenge. Returns the command fields on success.
-spec verify_registration(map()) -> {ok, map()} | {error, atom()}.
verify_registration(Map) ->
    Name = maps:get(<<"entity_name">>, Map, undefined),
    Did  = maps:get(<<"did">>, Map, undefined),
    Pub  = maps:get(<<"pubkey">>, Map, undefined),
    Sig  = maps:get(<<"signature">>, Map, undefined),
    Ts   = maps:get(<<"ts">>, Map, undefined),
    verify_fields(Name, Did, Pub, Sig, Ts).

verify_fields(Name, Did, PubB64, SigB64, Ts)
  when is_binary(Name), is_binary(Did), is_binary(PubB64),
       is_binary(SigB64), is_binary(Ts), Name =/= <<>>, Did =/= <<>> ->
    case {b64(PubB64), b64(SigB64)} of
        {{ok, Pub}, {ok, Sig}} when byte_size(Pub) =:= 32 ->
            Challenge = hecate_spartan_identity:registration_challenge(Did, Ts),
            case hecate_spartan_identity:verify_entity_sig(Challenge, Sig, Pub) of
                true  -> {ok, #{entity_name => Name, did => Did, pubkey => Pub,
                                registered_at => erlang:system_time(millisecond)}};
                false -> {error, bad_signature}
            end;
        {{ok, _}, {ok, _}} -> {error, invalid_pubkey};
        _                  -> {error, invalid_base64}
    end;
verify_fields(_, _, _, _, _) ->
    {error, missing_fields}.

%% --- Internal ---

b64(B) ->
    try {ok, base64:decode(B)} catch _:_ -> {error, bad_base64} end.

decode(Body) ->
    try {ok, jsx:decode(Body, [return_maps])} catch _:_ -> {error, bad_json} end.

realm() ->
    try hecate_om_identity:realm() of
        R when is_binary(R), R =/= <<>> -> R;
        _                               -> default_realm()
    catch _:_ -> default_realm()
    end.

default_realm() -> <<"io.macula.spartans">>.

reply_json(Code, Map, Req0, State) ->
    Body = jsx:encode(Map),
    Req = cowboy_req:reply(Code,
                           #{<<"content-type">> => <<"application/json">>},
                           Body, Req0),
    {ok, Req, State}.

fmt(T) -> iolist_to_binary(io_lib:format("~p", [T])).
