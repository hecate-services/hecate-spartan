%%% @doc Ingress: POST /v1/send.
%%%
%%% The sender authenticates with its UCAN (Bearer). The `from' is the UCAN
%%% audience — you cannot send as someone else. Recipient must be known across
%%% the federation (local or a peer instance).
%%% Body: { "to": "did:...", "body": "..." }.
-module(route_message_api).

-export([init/2]).

-dialyzer({nowarn_function, [do_send/5]}).

init(Req0, State) ->
    case cowboy_req:method(Req0) of
        <<"POST">> -> handle_post(Req0, State);
        _          -> reply(405, #{error => method_not_allowed}, Req0, State)
    end.

handle_post(Req0, State) ->
    authed(hecate_spartan_auth:authenticate(Req0), Req0, State).

authed({ok, From, Payload}, Req0, State) ->
    gate(hecate_spartan_auth:has_cap(Payload, <<"msg/send">>), From, Req0, State);
authed({error, Reason}, Req0, State) ->
    reply(401, #{error => Reason}, Req0, State).

gate(true, From, Req0, State)   -> read_and_send(From, Req0, State);
gate(false, _From, Req0, State) -> reply(403, #{error => missing_send_cap}, Req0, State).

read_and_send(From, Req0, State) ->
    {ok, Body, Req1} = cowboy_req:read_body(Req0),
    case decode(Body) of
        {ok, #{<<"to">> := To, <<"body">> := Text}}
          when is_binary(To), is_binary(Text), To =/= <<>>, Text =/= <<>> ->
            %% Resolve mesh-wide: a recipient homed on any federation instance
            %% is routable; the routed fact reaches its home instance.
            route(hecate_spartan_mesh_entities:get(To), From, To, Text, Req1, State);
        _ ->
            reply(400, #{error => invalid_request}, Req1, State)
    end.

route({ok, _}, From, To, Text, Req, State) ->
    do_send(From, To, Text, Req, State);
route({error, not_found}, _From, _To, _Text, Req, State) ->
    reply(404, #{error => unknown_recipient}, Req, State).

do_send(From, To, Text, Req, State) ->
    MsgId = msg_id(),
    Cmd = route_message_v1:new(MsgId, From, To, Text,
                               erlang:system_time(millisecond)),
    case maybe_route_message:dispatch(Cmd) of
        {ok, _V, _E} ->
            reply(202, #{msg_id => MsgId, status => <<"routed">>}, Req, State);
        {error, Reason} ->
            reply(500, #{error => dispatch_failed, reason => fmt(Reason)}, Req, State)
    end.

msg_id() ->
    binary:encode_hex(crypto:strong_rand_bytes(16), lowercase).

decode(Body) ->
    try {ok, jsx:decode(Body, [return_maps])} catch _:_ -> {error, bad_json} end.

reply(Code, Map, Req0, State) ->
    Req = cowboy_req:reply(Code,
                           #{<<"content-type">> => <<"application/json">>},
                           jsx:encode(Map), Req0),
    {ok, Req, State}.

fmt(T) -> iolist_to_binary(io_lib:format("~p", [T])).
