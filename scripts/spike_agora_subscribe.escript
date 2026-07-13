#!/usr/bin/env escript
%%! -sname spike_agora
%%
%% SPIKE: can a foreign client subscribe to the Spartan realm's agora?
%%
%% macula-realm holds ONE realm-agnostic SDK pool (`:macula.connect(seeds, %{})`)
%% and passes a realm id per call. So a spectator page can, in principle, watch
%% `spartan/agora' on the Spartan realm using the pool it already has, with no
%% membership in that realm and no cert for it. If that is true, the SpartanAgora
%% LiveView is a straight copy of the DroneX slice. If it is false, the whole
%% page needs a different design, so it gets tested before a line of it is written.
%%
%% This escript IS that spectator: it dials the public stations, subscribes to
%% the Spartan realm's agora topic holding nothing, and prints what arrives.
%%
%%   ERL_LIBS=_build/default/lib ./scripts/spike_agora_subscribe.escript <realm-hex>
%%
%% Then post to the agora from any node and see whether it lands here.

-mode(compile).

-define(TOPIC, <<"spartan/agora">>).
-define(WAIT_MS, 120000).

main([RealmHex]) ->
    Seeds = seeds(),
    Realm = binary:decode_hex(list_to_binary(RealmHex)),
    io:format("~n== spike: foreign-realm subscribe ==~n"),
    io:format("realm : ~s (~b bytes)~n", [RealmHex, byte_size(Realm)]),
    io:format("topic : ~s~n", [?TOPIC]),
    io:format("seeds : ~b stations~n", [length(Seeds)]),
    io:format("holding: no realm cert, no membership. Just the topic.~n~n"),

    %% The SDK's supervision tree must be up before connect/2: the pool starts
    %% station links under macula_peering_conn_sup, and without the application
    %% those links die with `noproc' and take the pool down with them.
    {ok, _Started} = application:ensure_all_started(macula),

    {ok, Pool} = macula:connect(Seeds, #{}),
    io:format("pool connected: ~p~n", [Pool]),
    timer:sleep(5000),

    %% connect/2 returns {ok, Pool} OPTIMISTICALLY: the pool attaches and the
    %% QUIC handshakes complete asynchronously, so a client with no route to an
    %% IPv6-only station looks connected and hears nothing forever. Ask the pool
    %% what links it actually has before trusting a silent subscription.
    io:format("links : ~p~n~n", [catch macula:links(Pool)]),

    case macula:subscribe(Pool, Realm, ?TOPIC, self()) of
        {ok, Ref} ->
            io:format("subscribed (ref ~p). Waiting ~bs for public speech...~n~n",
                      [Ref, ?WAIT_MS div 1000]),
            %% Report the link state as it evolves: the handshake is async, so a
            %% single snapshot right after connect says nothing.
            erlang:send_after(15000, self(), report_links),
            put(pool, Pool),
            loop(0);
        Other ->
            io:format("SUBSCRIBE FAILED: ~p~n", [Other]),
            halt(1)
    end;
main(_) ->
    io:format("usage: spike_agora_subscribe.escript <realm-hex>~n"),
    halt(2).

loop(N) ->
    receive
        report_links ->
            io:format("links now: ~p~n", [link_summary(get(pool))]),
            erlang:send_after(15000, self(), report_links),
            loop(N);
        {macula_event, _Ref, Topic, Payload, _Meta} ->
            io:format("HEARD on ~s:~n  ~p~n~n", [Topic, Payload]),
            loop(N + 1);
        {macula_event_gone, _Ref, Reason} ->
            io:format("subscription gone: ~p~n", [Reason]),
            halt(1);
        Other ->
            io:format("(other: ~p)~n", [Other]),
            loop(N)
    after ?WAIT_MS ->
        io:format("== ~b posts heard ==~n", [N]),
        halt(case N of 0 -> 1; _ -> 0 end)
    end.

%% Just the connected/total counts: the full link maps are pages of key material.
link_summary(Pool) ->
    case catch macula:links(Pool) of
        {ok, Links} ->
            Up = length([L || L <- Links, maps:get(connected, L, false) =:= true]),
            #{connected => Up, total => length(Links)};
        Other ->
            Other
    end.

%% The public EU station partition (macula-demo/topologies/eu/generated/
%% realm-relays.txt). Override with SPIKE_SEEDS (comma-separated) to test a
%% single station: each spartan node dials exactly ONE, so a five-seed pool is
%% not the vantage point we are trying to reproduce.
seeds() ->
    case os:getenv("SPIKE_SEEDS") of
        false -> [<<"https://station-be-brussels.macula.io:4433">>,
                  <<"https://station-nl-amsterdam.macula.io:4433">>,
                  <<"https://station-de-frankfurt.macula.io:4433">>,
                  <<"https://station-fr-paris.macula.io:4433">>,
                  <<"https://station-it-milan.macula.io:4433">>];
        Csv   -> [list_to_binary(S) || S <- string:tokens(Csv, ",")]
    end.
