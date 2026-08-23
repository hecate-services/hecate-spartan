%%% @doc Tests for L1 self-modification: a mind's own bounded, declared
%%% parameters. Pure schema/coercion first (no store); then a live-soul round
%%% trip (mirrors soul_tests.erl's fixture) proving a retune persists, is
%%% bounded, and is visible to mind_tools:execute/2 exactly as evolve_self is.
-module(mind_tunables_tests).

-include_lib("eunit/include/eunit.hrl").

%% --- schema ---

schema_ids_are_unique_test() ->
    Ids = [Id || #{id := Id} <- mind_tunables:schema()],
    ?assertEqual(lists:usort(Ids), lists:sort(Ids)).

schema_has_mindfulness_and_recall_k_test() ->
    Ids = [Id || #{id := Id} <- mind_tunables:schema()],
    ?assert(lists:member(mindfulness, Ids)),
    ?assert(lists:member(memory_recall_k, Ids)).

%% --- live-soul round trip ---

mind_tunables_test_() ->
    {foreach, fun setup/0, fun cleanup/1,
     [fun defaults_before_any_retune/1,
      fun retune_persists_and_reads_back/1,
      fun out_of_range_is_rejected_and_unchanged/1,
      fun wrong_type_is_rejected/1,
      fun unknown_parameter_is_rejected/1,
      fun retune_survives_reopen/1,
      fun tool_dispatch_retunes_and_acks/1,
      fun tool_dispatch_reports_rejection_without_changing_anything/1]}.

setup() ->
    Dir = iolist_to_binary(filename:join(
        ["/tmp", "spartan_tunables_test",
         integer_to_list(erlang:unique_integer([positive]))])),
    _ = os:cmd("rm -rf " ++ binary_to_list(Dir)),
    Dir.

cleanup(Dir) ->
    _ = os:cmd("rm -rf " ++ binary_to_list(Dir)),
    ok.

open_fresh(Dir) ->
    Did = <<"did:test:", (integer_to_binary(erlang:unique_integer([positive])))/binary>>,
    {ok, _Id} = soul:open(Did, Dir, #{name           => <<"testmind">>,
                                      genesis_version => <<"1">>,
                                      founding_brief  => <<"a mind under test">>}),
    Did.

defaults_before_any_retune(Dir) ->
    fun() ->
        Did = open_fresh(Dir),
        ?assertEqual(true, mind_tunables:current(Did, mindfulness)),
        ?assertEqual(2, mind_tunables:current(Did, memory_recall_k)),
        ?assertEqual(not_set, mind_tunables:retuned(Did, mindfulness))
    end.

retune_persists_and_reads_back(Dir) ->
    fun() ->
        Did = open_fresh(Dir),
        ?assertEqual({ok, false}, mind_tunables:retune(Did, mindfulness, false)),
        ?assertEqual(false, mind_tunables:current(Did, mindfulness)),
        ?assertEqual({ok, false}, mind_tunables:retuned(Did, mindfulness)),
        %% the OTHER knob is untouched
        ?assertEqual(2, mind_tunables:current(Did, memory_recall_k)),
        ?assertEqual({ok, 8}, mind_tunables:retune(Did, memory_recall_k, 8)),
        ?assertEqual(8, mind_tunables:current(Did, memory_recall_k)),
        ?assertEqual(false, mind_tunables:current(Did, mindfulness))
    end.

out_of_range_is_rejected_and_unchanged(Dir) ->
    fun() ->
        Did = open_fresh(Dir),
        ?assertEqual({error, {out_of_range, 99, {0, 20}}},
                     mind_tunables:retune(Did, memory_recall_k, 99)),
        ?assertEqual(2, mind_tunables:current(Did, memory_recall_k))
    end.

wrong_type_is_rejected(Dir) ->
    fun() ->
        Did = open_fresh(Dir),
        ?assertEqual({error, {not_a_boolean, 1}},
                     mind_tunables:retune(Did, mindfulness, 1)),
        ?assertEqual({error, {not_an_integer, true}},
                     mind_tunables:retune(Did, memory_recall_k, true)),
        ?assertEqual(true, mind_tunables:current(Did, mindfulness))
    end.

unknown_parameter_is_rejected(Dir) ->
    fun() ->
        Did = open_fresh(Dir),
        ?assertEqual({error, {unknown_tunable, bogus}},
                     mind_tunables:retune(Did, bogus, 1))
    end.

retune_survives_reopen(Dir) ->
    fun() ->
        Did = open_fresh(Dir),
        {ok, false} = mind_tunables:retune(Did, mindfulness, false),
        {ok, _Id2} = soul:open(Did, Dir, #{name           => <<"ignored">>,
                                           genesis_version => <<"1">>,
                                           founding_brief  => <<"ignored">>}),
        ?assertEqual(false, mind_tunables:current(Did, mindfulness))
    end.

%% --- via the tool a mind actually calls ---

tool_dispatch_retunes_and_acks(Dir) ->
    fun() ->
        Did = open_fresh(Dir),
        Call = #{name => <<"retune_self">>,
                 args => #{<<"parameter">> => <<"memory_recall_k">>,
                           <<"value">>     => <<"5">>,
                           <<"rationale">> => <<"the square is quiet lately">>}},
        {ok, #{ack := Ack}} = mind_tools:execute(Call, #{did => Did}),
        ?assert(contains(Ack, <<"retuned to 5">>)),
        ?assertEqual(5, mind_tunables:current(Did, memory_recall_k))
    end.

tool_dispatch_reports_rejection_without_changing_anything(Dir) ->
    fun() ->
        Did = open_fresh(Dir),
        Call = #{name => <<"retune_self">>,
                 args => #{<<"parameter">> => <<"memory_recall_k">>,
                           <<"value">>     => <<"500">>,
                           <<"rationale">> => <<"more is better">>}},
        {ok, #{ack := Ack}} = mind_tools:execute(Call, #{did => Did}),
        ?assert(contains(Ack, <<"retune rejected">>)),
        ?assertEqual(2, mind_tunables:current(Did, memory_recall_k))
    end.

contains(Hay, Needle) -> binary:match(Hay, Needle) =/= nomatch.
