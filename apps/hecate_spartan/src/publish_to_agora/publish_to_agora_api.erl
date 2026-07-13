%%% @doc Ingress: POST /v1/agora (speak in public) + GET /v1/agora (read the
%%% square).
%%%
%%% POST body: { "body": "...", "in_reply_to": "<post_id>" }  (in_reply_to optional)
%%% GET  query: ?limit=N  (default 50)
%%%
%%% The `from' is the UCAN audience: an entity speaks as itself, never as
%%% another. Posting needs `agora/post'; reading needs `agora/read'.
-module(publish_to_agora_api).

-export([init/2]).

-dialyzer({nowarn_function, [do_post/4]}).

-define(DEFAULT_LIMIT, 50).
-define(MAX_LIMIT, 200).

init(Req0, State) ->
    case cowboy_req:method(Req0) of
        <<"POST">> -> handle_post(Req0, State);
        <<"GET">>  -> handle_get(Req0, State);
        _          -> reply(405, #{error => method_not_allowed}, Req0, State)
    end.

%% --- speak ---

handle_post(Req0, State) ->
    case hecate_spartan_auth:authenticate(Req0) of
        {ok, From, Payload} ->
            gate_post(hecate_spartan_auth:has_cap(Payload, <<"agora/post">>),
                      From, Req0, State);
        {error, Reason} ->
            reply(401, #{error => Reason}, Req0, State)
    end.

gate_post(false, _From, Req, State) ->
    reply(403, #{error => missing_agora_post_cap}, Req, State);
gate_post(true, From, Req0, State) ->
    {ok, Body, Req1} = cowboy_req:read_body(Req0),
    case decode(Body) of
        {ok, #{<<"body">> := Text} = M} when is_binary(Text), Text =/= <<>> ->
            do_post(From, Text, in_reply_to(M), {Req1, State});
        _ ->
            reply(400, #{error => invalid_request}, Req1, State)
    end.

do_post(From, Text, InReplyTo, {Req, State}) ->
    PostId = post_id(),
    Cmd = publish_to_agora_v1:new(PostId, From, Text, InReplyTo,
                                  erlang:system_time(millisecond)),
    case maybe_publish_to_agora:dispatch(Cmd) of
        {ok, _V, _E} ->
            reply(202, #{post_id => PostId, status => <<"published">>}, Req, State);
        {error, Reason} ->
            reply(500, #{error => dispatch_failed, reason => fmt(Reason)}, Req, State)
    end.

%% --- read ---

handle_get(Req0, State) ->
    case hecate_spartan_auth:authenticate(Req0) of
        {ok, _Did, Payload} ->
            gate_read(hecate_spartan_auth:has_cap(Payload, <<"agora/read">>),
                      Req0, State);
        {error, Reason} ->
            reply(401, #{error => Reason}, Req0, State)
    end.

gate_read(false, Req, State) ->
    reply(403, #{error => missing_agora_read_cap}, Req, State);
gate_read(true, Req, State) ->
    Posts = [json_post(P) || P <- hecate_spartan_agora:recent(limit(Req))],
    reply(200, #{posts => Posts}, Req, State).

limit(Req) ->
    #{limit := L} = cowboy_req:match_qs([{limit, int, ?DEFAULT_LIMIT}], Req),
    min(max(L, 1), ?MAX_LIMIT).

json_post(P) ->
    #{post_id     => maps:get(post_id, P),
      from        => maps:get(from, P),
      body        => maps:get(body, P),
      in_reply_to => null_if_undefined(maps:get(in_reply_to, P, undefined)),
      posted_at   => maps:get(posted_at, P, 0)}.

%% --- Internal ---

in_reply_to(#{<<"in_reply_to">> := R}) when is_binary(R), R =/= <<>> -> R;
in_reply_to(_)                                                       -> undefined.

null_if_undefined(undefined) -> null;
null_if_undefined(V)         -> V.

post_id() ->
    binary:encode_hex(crypto:strong_rand_bytes(16), lowercase).

decode(Body) ->
    try {ok, jsx:decode(Body, [return_maps])} catch _:_ -> {error, bad_json} end.

reply(Code, Map, Req0, State) ->
    Req = cowboy_req:reply(Code,
                           #{<<"content-type">> => <<"application/json">>},
                           jsx:encode(Map), Req0),
    {ok, Req, State}.

fmt(T) -> iolist_to_binary(io_lib:format("~p", [T])).
