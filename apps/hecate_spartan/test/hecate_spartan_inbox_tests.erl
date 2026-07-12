%%% @doc Tests for the in-process inbox (queue + push + backlog).
-module(hecate_spartan_inbox_tests).
-include_lib("eunit/include/eunit.hrl").

inbox_flow_test() ->
    {ok, Pid} = hecate_spartan_inbox:start_link(),
    Did = <<"did:key:e1">>,
    M1 = #{msg_id => <<"m1">>, from => <<"did:key:e2">>,
           body => <<"hi">>, sent_at => 1},

    %% No receiver yet: queues as backlog.
    ok = hecate_spartan_inbox:deliver(Did, M1),
    timer:sleep(50),
    ?assertEqual([M1], hecate_spartan_inbox:pending(Did)),

    %% Subscribing drains the backlog and clears the queue.
    ?assertEqual([M1], hecate_spartan_inbox:subscribe(Did)),
    ?assertEqual([], hecate_spartan_inbox:pending(Did)),

    %% Now delivery pushes straight to the subscriber (this process).
    M2 = #{msg_id => <<"m2">>, from => <<"did:key:e2">>,
           body => <<"yo">>, sent_at => 2},
    ok = hecate_spartan_inbox:deliver(Did, M2),
    receive
        {spartan_msg, Got} -> ?assertEqual(M2, Got)
    after 1000 ->
        ?assert(false)
    end,

    gen_server:stop(Pid).

dedup_test() ->
    {ok, Pid} = hecate_spartan_inbox:start_link(),
    Did = <<"did:key:d">>,
    M = #{msg_id => <<"dup1">>, from => <<"z">>, body => <<"b">>, sent_at => 1},

    %% Same {recipient, msg_id} delivered twice: queued once only.
    ok = hecate_spartan_inbox:deliver(Did, M),
    ok = hecate_spartan_inbox:deliver(Did, M),
    timer:sleep(50),
    ?assertEqual(1, length(hecate_spartan_inbox:pending(Did))),

    gen_server:stop(Pid).

broadcast_fanout_survives_dedup_test() ->
    {ok, Pid} = hecate_spartan_inbox:start_link(),
    %% One msg_id, two recipients (broadcast): both must queue — dedup is
    %% per recipient, not global.
    B = #{msg_id => <<"bc1">>, from => <<"z">>, body => <<"all">>, sent_at => 1},
    ok = hecate_spartan_inbox:deliver(<<"did:key:x">>, B),
    ok = hecate_spartan_inbox:deliver(<<"did:key:y">>, B),
    timer:sleep(50),
    ?assertEqual(1, length(hecate_spartan_inbox:pending(<<"did:key:x">>))),
    ?assertEqual(1, length(hecate_spartan_inbox:pending(<<"did:key:y">>))),
    gen_server:stop(Pid).

isolation_test() ->
    {ok, Pid} = hecate_spartan_inbox:start_link(),
    ok = hecate_spartan_inbox:deliver(<<"did:key:a">>,
                                      #{msg_id => <<"x">>, from => <<"z">>,
                                        body => <<"b">>, sent_at => 1}),
    timer:sleep(50),
    ?assertEqual([], hecate_spartan_inbox:pending(<<"did:key:b">>)),
    ?assertEqual(1, length(hecate_spartan_inbox:pending(<<"did:key:a">>))),
    gen_server:stop(Pid).
