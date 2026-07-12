%%% @doc Ingress: GET /v1/receive — Server-Sent Events stream of an entity's
%%% inbox.
%%%
%%% The entity authenticates with its UCAN (Bearer, msg/recv cap). We subscribe
%%% it to its inbox, flush any backlog, then stream each new message as an SSE
%%% `data:' frame. A periodic comment keeps the connection (and cowboy's idle
%%% timer) alive. Disconnect unsubscribes via the inbox process monitor.
-module(receive_api).

-export([init/2, info/3, terminate/3]).

-define(PING_MS, 25000).

init(Req0, _State) ->
    authorize(cowboy_req:method(Req0), Req0).

authorize(<<"GET">>, Req0) ->
    case hecate_spartan_auth:authenticate(Req0) of
        {ok, Did, Payload} ->
            case hecate_spartan_auth:has_cap(Payload, <<"msg/recv">>) of
                true  -> start_stream(Did, Req0);
                false -> {ok, err(403, missing_recv_cap, Req0), #{}}
            end;
        {error, Reason} ->
            {ok, err(401, Reason, Req0), #{}}
    end;
authorize(_Other, Req0) ->
    {ok, err(405, method_not_allowed, Req0), #{}}.

start_stream(Did, Req0) ->
    Backlog = hecate_spartan_inbox:subscribe(Did),
    Req = cowboy_req:stream_reply(200,
        #{<<"content-type">>  => <<"text/event-stream">>,
          <<"cache-control">> => <<"no-cache">>,
          <<"connection">>    => <<"keep-alive">>}, Req0),
    _ = [send_event(Req, M) || M <- Backlog],
    erlang:send_after(?PING_MS, self(), ping),
    {cowboy_loop, Req, #{did => Did}}.

info({spartan_msg, Msg}, Req, State) ->
    send_event(Req, Msg),
    {ok, Req, State};
info(ping, Req, State) ->
    ok = cowboy_req:stream_body(<<": ping\n\n">>, nofin, Req),
    erlang:send_after(?PING_MS, self(), ping),
    {ok, Req, State};
info(_Info, Req, State) ->
    {ok, Req, State}.

terminate(_Reason, _Req, #{did := Did}) ->
    hecate_spartan_inbox:unsubscribe(Did, self()),
    ok;
terminate(_Reason, _Req, _State) ->
    ok.

send_event(Req, Msg) ->
    ok = cowboy_req:stream_body([<<"data: ">>, jsx:encode(Msg), <<"\n\n">>],
                                nofin, Req).

err(Code, Reason, Req) ->
    cowboy_req:reply(Code,
                     #{<<"content-type">> => <<"application/json">>},
                     jsx:encode(#{error => Reason}), Req).
