%%% @doc The gate between a draft and the square.
%%%
%%% The behaviour that matters most here is the one that is easiest to get
%%% wrong and impossible to notice: it must FAIL OPEN. A society silenced
%%% because an embedding service is down is a worse failure than an echo,
%%% and a silent one -- nobody notices posts that were never made.
-module(novelty_tests).
-include_lib("eunit/include/eunit.hrl").

%% --- similarity, pure ---

identical_vectors_are_identical_test() ->
    ?assert(novelty:similarity([1.0, 2.0, 3.0], [1.0, 2.0, 3.0]) > 0.999).

orthogonal_vectors_share_nothing_test() ->
    ?assertEqual(0.0, novelty:similarity([1.0, 0.0], [0.0, 1.0])).

opposite_vectors_are_negative_test() ->
    ?assert(novelty:similarity([1.0, 0.0], [-1.0, 0.0]) < -0.999).

%% Scale must not matter: an embedder that returns un-normalised vectors
%% would otherwise read as "less similar" purely for being longer.
magnitude_does_not_change_direction_test() ->
    A = [3.0, 4.0],
    ?assert(abs(novelty:similarity(A, [30.0, 40.0]) - 1.0) < 0.0001).

mismatched_shapes_are_no_similarity_test() ->
    ?assertEqual(0.0, novelty:similarity([1.0], [1.0, 2.0])),
    ?assertEqual(0.0, novelty:similarity([], [])),
    ?assertEqual(0.0, novelty:similarity(not_a_vector, [1.0])).

%% A zero vector has no direction, so it is similar to nothing. Dividing by
%% its magnitude would crash the mind mid-turn.
zero_vector_does_not_divide_by_zero_test() ->
    ?assertEqual(0.0, novelty:similarity([0.0, 0.0], [1.0, 2.0])).

%% --- the threshold ---

threshold_defaults_conservatively_test() ->
    true = os:unsetenv("HECATE_MIND_NOVELTY"),
    %% A false silence destroys a post nobody will ever see; a false pass
    %% costs one redundant paragraph. The default leans to speaking.
    ?assert(novelty:threshold() >= 0.85),
    ?assert(novelty:threshold() =< 0.95).

threshold_is_tunable_test() ->
    true = os:putenv("HECATE_MIND_NOVELTY", "0.75"),
    ?assertEqual(0.75, novelty:threshold()),
    true = os:unsetenv("HECATE_MIND_NOVELTY").

nonsense_threshold_falls_back_test() ->
    Default = begin true = os:unsetenv("HECATE_MIND_NOVELTY"), novelty:threshold() end,
    [begin
         true = os:putenv("HECATE_MIND_NOVELTY", V),
         ?assertEqual(Default, novelty:threshold())
     end || V <- ["", "loose", "-1", "0", "2.5"]],
    true = os:unsetenv("HECATE_MIND_NOVELTY").

%% --- permits: what is not gated at all ---

%% Unprompted speech is about no story, so there is no thread it could be
%% redundant within. A committee's synthesis must never be silenced.
unprompted_speech_is_never_an_echo_test() ->
    ?assertEqual(ok, novelty:permits(<<"a committee's conclusion">>, undefined)),
    ?assertEqual(ok, novelty:permits(<<"words">>, not_a_stimulus)).

%% Nothing has been said about this story yet, so nothing can be echoed --
%% and this path must not reach the embedder at all.
first_word_on_a_story_always_passes_test() ->
    ?assertEqual(ok, novelty:permits(<<"the first take">>,
                                     #{item_id => <<"nobody-has-spoken">>})).

a_story_with_no_id_is_not_a_thread_test() ->
    ?assertEqual(ok, novelty:permits(<<"words">>, #{item_id => <<>>})),
    ?assertEqual(ok, novelty:permits(<<"words">>, #{})).

%% --- permits: failing open ---

%% THE test. `embed_enabled = false' is exactly what a dark mesh looks like
%% to this module, and the mind must speak anyway.
fails_open_when_the_embedder_is_unavailable_test_() ->
    {setup,
     fun() ->
         {ok, Pid} = hecate_spartan_agora:start_link(),
         ok = application:set_env(hecate_spartan, embed_enabled, false),
         ok = hecate_spartan_agora:post(
                #{post_id => <<"p1">>, from => <<"did:key:a">>,
                  body => <<"the evacuation radius is the story">>,
                  posted_at => 100, stimulus => #{item_id => <<"s1">>}}),
         Pid
     end,
     fun(Pid) ->
         ok = application:unset_env(hecate_spartan, embed_enabled),
         gen_server:stop(Pid)
     end,
     fun(_) ->
         [?_assertEqual(ok, novelty:permits(<<"the evacuation radius is the story">>,
                                            #{item_id => <<"s1">>}))]
     end}.
