%%% @doc Bounded threads: a story that ends rather than one that stops.
%%%
%%% Without a cap nothing in this square ever ENDS. The record was forty
%%% openings and no endings, because a story does not close, the minds
%%% simply drift onto other stimuli. These pin the cap, and pin the two
%%% things that must NOT be capped.
-module(bounded_threads_tests).
-include_lib("eunit/include/eunit.hrl").

-define(ME, <<"did:key:me">>).
-define(PEER, <<"did:key:peer">>).

news(ItemId) ->
    #{type => news_item, item_id => ItemId, from => <<"hecate-news">>,
      title => <<"a headline">>, source => <<"zeit">>,
      body => <<"[NEWS] something happened">>}.

%% --- the pure gate (decide/6) ---

room_lets_a_ready_mind_speak_test() ->
    ?assertMatch({ok, _}, spartan_mind:decide(news(<<"s1">>), ?ME, 0, 100000, 1000, true)).

a_full_thread_declines_test() ->
    ?assertEqual({declined, thread_full},
                 spartan_mind:decide(news(<<"s1">>), ?ME, 0, 100000, 1000, false)).

%% Checked BEFORE the cooldown, so a mind whose one turn in five minutes has
%% come round is not spent on a story that is already closed.
a_full_thread_outranks_the_cooldown_test() ->
    ?assertEqual({declined, thread_full},
                 spartan_mind:decide(news(<<"s1">>), ?ME, 100000, 100000, 1000, false)).

%% Own speech is still the first thing checked: a mind hearing itself back
%% has missed nothing, whatever the thread is doing.
own_speech_still_outranks_everything_test() ->
    Mine = (news(<<"s1">>))#{from => ?ME},
    ?assertEqual({declined, own_speech},
                 spartan_mind:decide(Mine, ?ME, 0, 100000, 1000, false)).

an_empty_body_is_still_nothing_test() ->
    ?assertEqual({declined, empty},
                 spartan_mind:decide(#{from => ?PEER, body => <<>>}, ?ME, 0, 1, 0, true)).

%% --- the cap ---

cap_defaults_to_a_conversation_test() ->
    true = os:unsetenv("HECATE_MIND_THREAD_CAP"),
    %% Enough for a claim, two answers and a correction; few enough that the
    %% square moves on.
    ?assert(spartan_mind:thread_cap() >= 2),
    ?assert(spartan_mind:thread_cap() =< 8).

cap_is_tunable_test() ->
    true = os:putenv("HECATE_MIND_THREAD_CAP", "2"),
    ?assertEqual(2, spartan_mind:thread_cap()),
    true = os:unsetenv("HECATE_MIND_THREAD_CAP").

nonsense_cap_falls_back_test() ->
    Default = begin true = os:unsetenv("HECATE_MIND_THREAD_CAP"),
                    spartan_mind:thread_cap() end,
    [begin
         true = os:putenv("HECATE_MIND_THREAD_CAP", V),
         ?assertEqual(Default, spartan_mind:thread_cap())
     end || V <- ["", "many", "0", "-3"]],
    true = os:unsetenv("HECATE_MIND_THREAD_CAP").

%% --- the synthesizer ---

%% One per society. Two would each close every thread and the square would
%% end twice.
synthesizer_is_off_unless_asked_test() ->
    true = os:unsetenv("HECATE_MIND_SYNTHESIZER"),
    ?assertNot(spartan_mind:synthesizer()),
    true = os:putenv("HECATE_MIND_SYNTHESIZER", "0"),
    ?assertNot(spartan_mind:synthesizer()),
    true = os:putenv("HECATE_MIND_SYNTHESIZER", "1"),
    ?assert(spartan_mind:synthesizer()),
    true = os:unsetenv("HECATE_MIND_SYNTHESIZER").

%% --- counting a thread, against a live feed ---

feed_test_() ->
    {setup,
     fun() -> {ok, Pid} = hecate_spartan_agora:start_link(), Pid end,
     fun(Pid) -> gen_server:stop(Pid) end,
     fun(_) ->
         [counts_only_this_story(),
          unprompted_speech_is_in_no_thread(),
          a_thread_is_open_until_somebody_closes_it(),
          a_synthesis_closes_it(),
          an_unknown_story_is_empty()]
     end}.

post(Id, ItemId, At) ->
    post(Id, ItemId, At, undefined).

post(Id, ItemId, At, Kind) ->
    #{post_id => Id, from => ?PEER, body => <<"words">>, posted_at => At,
      kind => Kind, stimulus => stimulus(ItemId)}.

stimulus(undefined) -> undefined;
stimulus(ItemId)    -> #{item_id => ItemId}.

counts_only_this_story() ->
    ok = hecate_spartan_agora:post(post(<<"a">>, <<"s1">>, 1)),
    ok = hecate_spartan_agora:post(post(<<"b">>, <<"s1">>, 2)),
    ok = hecate_spartan_agora:post(post(<<"c">>, <<"s2">>, 3)),
    [?_assertEqual(2, hecate_spartan_agora:thread_size(<<"s1">>)),
     ?_assertEqual(1, hecate_spartan_agora:thread_size(<<"s2">>)),
     %% Oldest first, so a closing brief reads in the order it was said.
     ?_assertEqual([<<"a">>, <<"b">>],
                   [maps:get(post_id, P) || P <- hecate_spartan_agora:thread(<<"s1">>)])].

%% A committee's post, a visitor's question, a silence: about no story, so in
%% no thread, and never capped.
unprompted_speech_is_in_no_thread() ->
    ok = hecate_spartan_agora:post(post(<<"loose">>, undefined, 4)),
    [?_assertEqual(0, hecate_spartan_agora:thread_size(<<>>)),
     ?_assertEqual([], hecate_spartan_agora:thread(undefined))].

a_thread_is_open_until_somebody_closes_it() ->
    ?_assertNot(hecate_spartan_agora:closed(<<"s1">>)).

a_synthesis_closes_it() ->
    ok = hecate_spartan_agora:post(post(<<"end">>, <<"s3">>, 5, synthesis)),
    [?_assert(hecate_spartan_agora:closed(<<"s3">>)),
     %% Ordinary speech does not close anything.
     ?_assertNot(hecate_spartan_agora:closed(<<"s2">>))].

an_unknown_story_is_empty() ->
    [?_assertEqual([], hecate_spartan_agora:thread(<<"never-heard-of-it">>)),
     ?_assertNot(hecate_spartan_agora:closed(<<"never-heard-of-it">>))].
