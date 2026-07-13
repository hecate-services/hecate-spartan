%%% @doc Ingress: POST /v1/activity — an entity reports what it is doing.
%%%
%%% Body: { "kind": "action|thought|speech|model|alert|cycle", "summary": "..." }
%%% The `did' is the UCAN audience: an agent reports as itself.
-module(report_activity_api).

-export([init/2]).

-dialyzer({nowarn_function, [do_report/4]}).

init(Req0, State) ->
    case cowboy_req:method(Req0) of
        <<"POST">> -> handle_post(Req0, State);
        _          -> reply(405, #{error => method_not_allowed}, Req0, State)
    end.

handle_post(Req0, State) ->
    case hecate_spartan_auth:authenticate(Req0) of
        {ok, Did, Payload} ->
            gate(hecate_spartan_auth:has_cap(Payload, <<"activity/report">>),
                 Did, Req0, State);
        {error, Reason} ->
            reply(401, #{error => Reason}, Req0, State)
    end.

gate(false, _Did, Req, State) ->
    reply(403, #{error => missing_activity_report_cap}, Req, State);
gate(true, Did, Req0, State) ->
    {ok, Body, Req1} = cowboy_req:read_body(Req0),
    case decode(Body) of
        {ok, #{<<"kind">> := K, <<"summary">> := S}}
          when is_binary(K), is_binary(S), S =/= <<>> ->
            do_report(Did, K, S, {Req1, State});
        _ ->
            reply(400, #{error => invalid_request}, Req1, State)
    end.

do_report(Did, Kind, Summary, {Req, State}) ->
    Id = activity_id(),
    Cmd = report_activity_v1:new(Id, Did, Kind, Summary,
                                 erlang:system_time(millisecond)),
    case maybe_report_activity:dispatch(Cmd) of
        {ok, _V, _E} ->
            reply(202, #{activity_id => Id}, Req, State);
        {error, unknown_kind} ->
            reply(400, #{error => unknown_kind}, Req, State);
        {error, Reason} ->
            reply(500, #{error => dispatch_failed, reason => fmt(Reason)}, Req, State)
    end.

activity_id() ->
    binary:encode_hex(crypto:strong_rand_bytes(16), lowercase).

decode(Body) ->
    try {ok, jsx:decode(Body, [return_maps])} catch _:_ -> {error, bad_json} end.

reply(Code, Map, Req0, State) ->
    Req = cowboy_req:reply(Code,
                           #{<<"content-type">> => <<"application/json">>},
                           jsx:encode(Map), Req0),
    {ok, Req, State}.

fmt(T) -> iolist_to_binary(io_lib:format("~p", [T])).
