%%% @doc Tests for L2 self-modification: a mind's own capability grants.
%%% Covers everything that does NOT require a live LLM call: the schema, the
%%% granted/has reads, and grant/2's two short-circuit paths (already granted;
%%% unknown id) that never reach the adversarial verifier. The verifier path
%%% itself (mind_verifier:verify/2, a real LLM call) is exercised by
%%% integration, same convention as evolve_self.
-module(mind_capabilities_tests).

-include_lib("eunit/include/eunit.hrl").

%% --- schema ---

schema_ids_are_unique_test() ->
    Ids = [Id || #{id := Id} <- mind_capabilities:schema()],
    ?assertEqual(lists:usort(Ids), lists:sort(Ids)).

schema_has_rag_search_and_reach_web_test() ->
    Ids = [Id || #{id := Id} <- mind_capabilities:schema()],
    ?assert(lists:member(rag_search, Ids)),
    ?assert(lists:member(reach_web, Ids)).

%% --- live-soul reads + short-circuit grant paths ---

mind_capabilities_test_() ->
    {foreach, fun setup/0, fun cleanup/1,
     [fun no_grants_by_default/1,
      fun granted_and_has_read_what_soul_holds/1,
      fun already_granted_is_a_free_no_op/1,
      fun unknown_capability_is_rejected_without_a_verify_call/1]}.

setup() ->
    Dir = iolist_to_binary(filename:join(
        ["/tmp", "spartan_capabilities_test",
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

no_grants_by_default(Dir) ->
    fun() ->
        Did = open_fresh(Dir),
        ?assertEqual([], mind_capabilities:granted(Did)),
        ?assertNot(mind_capabilities:has(Did, rag_search)),
        ?assertNot(mind_capabilities:has(Did, reach_web))
    end.

granted_and_has_read_what_soul_holds(Dir) ->
    fun() ->
        Did = open_fresh(Dir),
        ok = soul:set_capabilities(Did, <<"rag_search\n">>),
        ?assertEqual([rag_search], mind_capabilities:granted(Did)),
        ?assert(mind_capabilities:has(Did, rag_search)),
        ?assertNot(mind_capabilities:has(Did, reach_web))
    end.

%% grant/2's already-granted branch never calls the verifier (no live LLM
%% needed to exercise it), so this is safe to run as a plain unit test.
already_granted_is_a_free_no_op(Dir) ->
    fun() ->
        Did = open_fresh(Dir),
        ok = soul:set_capabilities(Did, <<"reach_web\n">>),
        ?assertEqual({ok, granted}, mind_capabilities:grant(Did, reach_web)),
        ?assertEqual([reach_web], mind_capabilities:granted(Did))
    end.

unknown_capability_is_rejected_without_a_verify_call(Dir) ->
    fun() ->
        Did = open_fresh(Dir),
        ?assertEqual({error, {unknown_capability, bogus}},
                     mind_capabilities:grant(Did, bogus)),
        ?assertEqual([], mind_capabilities:granted(Did))
    end.
