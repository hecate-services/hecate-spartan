%%% @doc Tests for the committee COORDINATOR's pure surface: drone selection
%%% from the lens roster, transcript rendering, and the scribe's prompt shape.
%%% A drone's own prompt (committee_drone:messages/3) is tested in
%%% committee_drone_tests.erl — it is the drone's responsibility now, not the
%%% coordinator's. The live deliberation (LLM calls, mesh publish, floor
%%% hand-off, supervision) is integration; here we cover everything that can
%%% be reasoned about without a backend or a store.
-module(committee_tests).

-include_lib("eunit/include/eunit.hrl").

%% --- drone selection ---

pick_drones_returns_requested_count_test() ->
    Drones = committee:pick_drones(3),
    ?assertEqual(3, length(Drones)),
    ?assert(lists:all(fun(#{name := N, lens := L}) ->
                          is_binary(N) andalso is_binary(L)
                      end, Drones)).

pick_drones_clamps_to_roster_size_test() ->
    %% Asking for more voices than there are lenses gives every lens, once.
    All = committee:pick_drones(99),
    Names = [N || #{name := N} <- All],
    ?assertEqual(length(Names), length(lists:usort(Names))),
    ?assert(length(All) =< 5).

pick_drones_defaults_on_nonsense_test() ->
    ?assertEqual(3, length(committee:pick_drones(0))),
    ?assertEqual(3, length(committee:pick_drones(-4))).

%% --- transcript rendering ---

render_transcript_joins_named_lines_test() ->
    T = [#{drone => <<"the operator">>, text => <<"Block it.">>},
         #{drone => <<"the skeptic">>, text => <<"Prove it first.">>}],
    ?assertEqual(<<"the operator: Block it.\n\nthe skeptic: Prove it first.">>,
                 committee:render_transcript(T)).

render_empty_transcript_is_empty_test() ->
    ?assertEqual(<<>>, committee:render_transcript([])).

%% --- scribe prompt ---

scribe_reads_question_and_transcript_test() ->
    T = [#{drone => <<"the adversary">>, text => <<"They pivot to SSH.">>}],
    [Sys, Usr] = committee:scribe_messages(<<"How bad?">>, T),
    ?assertEqual(<<"system">>, maps:get(<<"role">>, Sys)),
    ?assertNotEqual(nomatch, binary:match(maps:get(<<"content">>, Sys), <<"How bad?">>)),
    ?assertNotEqual(nomatch, binary:match(maps:get(<<"content">>, Usr), <<"They pivot to SSH.">>)).

%% --- convening validation (the paths that return before touching the sup) ---

convene_rejects_missing_fields_test() ->
    ?assertEqual({error, invalid_committee}, convene_committee:convene(#{})),
    ?assertEqual({error, invalid_committee},
                 convene_committee:convene(#{convener => <<"did:x">>})).

convene_rejects_empty_question_test() ->
    ?assertEqual({error, invalid_committee},
                 convene_committee:convene(#{convener => <<"did:x">>, question => <<>>})).

convene_rejects_empty_convener_test() ->
    ?assertEqual({error, invalid_committee},
                 convene_committee:convene(#{convener => <<>>, question => <<"q">>})).
