%%% @doc Tests for self-alerts: the token-clock scheduler. Scheduling by a token
%%% budget, firing when the budget is reached, and surviving a restart on disk.
-module(self_alerts_tests).

-include_lib("eunit/include/eunit.hrl").

schedule_sets_fire_at_test() ->
    [Alert] = self_alerts:schedule([], 1000, 500, <<"revisit the grid question">>),
    ?assertEqual(1500, maps:get(fire_at, Alert)),
    ?assertEqual(<<"revisit the grid question">>, maps:get(note, Alert)).

zero_budget_still_arms_test() ->
    %% A non-positive budget must not fire instantly on the same token count.
    [Alert] = self_alerts:schedule([], 1000, 0, <<"soon">>),
    ?assert(maps:get(fire_at, Alert) > 1000).

fire_due_partitions_test() ->
    A = self_alerts:schedule([], 0, 100, <<"early">>),
    B = self_alerts:schedule(A, 0, 5000, <<"late">>),
    {Due, Pending} = self_alerts:fire_due(B, 200),
    ?assertEqual([<<"early">>], [maps:get(note, X) || X <- Due]),
    ?assertEqual([<<"late">>], [maps:get(note, X) || X <- Pending]).

nothing_due_yet_test() ->
    A = self_alerts:schedule([], 0, 5000, <<"later">>),
    ?assertEqual({[], A}, self_alerts:fire_due(A, 100)).

save_load_roundtrip_test() ->
    Dir = tmp_dir(),
    Did = <<"did:test:alerts">>,
    Alerts = self_alerts:schedule([], 0, 3000, <<"persisted reminder">>),
    ok = self_alerts:save(Dir, Did, Alerts),
    ?assertEqual(Alerts, self_alerts:load(Dir, Did)).

load_missing_is_empty_test() ->
    ?assertEqual([], self_alerts:load(tmp_dir(), <<"did:test:none">>)).

tmp_dir() ->
    D = filename:join(["/tmp", "spartan_alerts_test",
                       integer_to_list(erlang:unique_integer([positive]))]),
    ok = filelib:ensure_dir(filename:join(D, ".keep")),
    unicode:characters_to_binary(D).
