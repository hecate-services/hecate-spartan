%%% @doc What a mind does with what it hears, before it thinks.
%%%
%%% Measured on 2026-09-03: one peer post reached every other mind about
%%% forty times in forty minutes, because the republisher says every recent
%%% post again once a minute and a mind kept no record of having heard it.
%%% Ninety-five percent of the stimulus stream was history, the one turn the
%%% cooldown allowed went to whichever copy arrived first, and in 21 posts no
%%% mind had answered another. These pin the four rules that changed that:
%%% history is marked and ignored, a post is heard once, a reply runs on its
%%% own clock, and a reply that lands mid-turn is kept rather than dropped.
-module(stimulus_hygiene_tests).

-include_lib("eunit/include/eunit.hrl").

-define(ME, <<"did:macula:spartan:ME">>).
-define(PEER, <<"did:macula:spartan:PEER">>).
-define(NOW, 10_000_000).

peer_post(Id, Story, PostedAt) ->
    #{type => agora_post, post_id => Id, from => ?PEER, body => <<"a take on ", Story/binary>>,
      posted_at => PostedAt,
      stimulus => #{item_id => Story, title => <<"t">>, source => <<"s">>}}.

news(Story) ->
    #{type => news_item, item_id => Story, from => <<"hecate-news">>,
      title => <<"a headline">>, source => <<"zeit">>, body => <<"[NEWS] something">>}.

%% --- what a fact is ---

a_fresh_peer_post_is_speech_test() ->
    ?assertEqual(peer, spartan_mind:kind_of(peer_post(<<"p1">>, <<"s1">>, ?NOW - 1000), ?ME, ?NOW)).

the_republisher_marks_history_and_a_mind_treats_it_so_test() ->
    Said = peer_post(<<"p1">>, <<"s1">>, ?NOW - 1000),
    Again = federation_agora:history(Said),
    ?assertEqual(1, maps:get(replay, Again)),
    ?assertEqual(replay, spartan_mind:kind_of(Again, ?ME, ?NOW)).

%% A peer on an older version republishes without the mark. Age catches it:
%% nothing said ten minutes ago is arriving live.
an_old_post_is_history_even_without_the_mark_test() ->
    ?assertEqual(replay, spartan_mind:kind_of(peer_post(<<"p1">>, <<"s1">>, ?NOW - 3_600_000), ?ME, ?NOW)).

own_fresh_speech_is_own_test() ->
    Mine = (peer_post(<<"p1">>, <<"s1">>, ?NOW - 1000))#{from => ?ME},
    ?assertEqual(own, spartan_mind:kind_of(Mine, ?ME, ?NOW)).

%% A mind's own post said again by its republisher is history like anyone
%% else's: there is one of those a minute per post, and none is an event.
own_speech_said_again_is_history_test() ->
    Mine = (peer_post(<<"p1">>, <<"s1">>, ?NOW - 1000))#{from => ?ME},
    ?assertEqual(replay, spartan_mind:kind_of(federation_agora:history(Mine), ?ME, ?NOW)),
    Old = (peer_post(<<"p1">>, <<"s1">>, ?NOW - 3_600_000))#{from => ?ME},
    ?assertEqual(replay, spartan_mind:kind_of(Old, ?ME, ?NOW)).

a_sensor_fact_opens_a_story_test() ->
    ?assertEqual(opening, spartan_mind:kind_of(news(<<"s1">>), ?ME, ?NOW)).

a_broadcast_is_neither_test() ->
    ?assertEqual(other, spartan_mind:kind_of(#{body => <<"sector 4 digest">>}, ?ME, ?NOW)),
    ?assertEqual(other, spartan_mind:kind_of(#{}, ?ME, ?NOW)),
    ?assertEqual(other, spartan_mind:kind_of(not_a_map, ?ME, ?NOW)).

%% --- hearing a post once ---

a_post_is_heard_once_test() ->
    H0 = spartan_mind:heard_new(),
    ?assertNot(spartan_mind:heard_has(<<"p1">>, H0)),
    H1 = spartan_mind:heard_add(<<"p1">>, H0),
    ?assert(spartan_mind:heard_has(<<"p1">>, H1)),
    ?assertNot(spartan_mind:heard_has(<<"p2">>, H1)).

a_post_with_no_id_cannot_be_deduped_and_is_not_test() ->
    H0 = spartan_mind:heard_new(),
    ?assertEqual(H0, spartan_mind:heard_add(undefined, H0)),
    ?assertNot(spartan_mind:heard_has(undefined, H0)).

the_memory_of_what_was_heard_is_bounded_test() ->
    Ids = [integer_to_binary(N) || N <- lists:seq(1, 600)],
    H = lists:foldl(fun spartan_mind:heard_add/2, spartan_mind:heard_new(), Ids),
    ?assert(spartan_mind:heard_has(<<"600">>, H)),
    ?assertNot(spartan_mind:heard_has(<<"1">>, H)).

%% --- two clocks ---

gate(Over) ->
    maps:merge(#{kind => peer, now => ?NOW, last_opened => 0, last_replied => 0,
                 cooldown => 300_000, reply_cooldown => 30_000, room => true},
               Over).

%% The opening cooldown is the cost brake and it does not apply to a reply: a
%% mind that opened a story a minute ago may still answer a peer about it.
a_reply_is_not_rationed_by_the_opening_clock_test() ->
    Reply = peer_post(<<"p2">>, <<"s1">>, ?NOW - 1000),
    ?assertMatch({ok, _}, spartan_mind:decide(Reply, gate(#{kind => peer, last_opened => ?NOW - 60_000}))).

an_opening_is_still_rationed_test() ->
    ?assertEqual({declined, cooldown},
                 spartan_mind:decide(news(<<"s9">>), gate(#{kind => opening, last_opened => ?NOW - 60_000}))).

%% And a reply has its own, shorter clock, so two minds cannot volley.
a_reply_right_after_a_reply_waits_test() ->
    Reply = peer_post(<<"p2">>, <<"s1">>, ?NOW - 1000),
    ?assertEqual({declined, reply_cooldown},
                 spartan_mind:decide(Reply, gate(#{kind => peer, last_replied => ?NOW - 5_000}))),
    ?assertMatch({ok, _},
                 spartan_mind:decide(Reply, gate(#{kind => peer, last_replied => ?NOW - 31_000}))).

%% A full thread outranks both clocks: no reply into a story that is closed.
a_full_thread_beats_both_clocks_test() ->
    Reply = peer_post(<<"p2">>, <<"s1">>, ?NOW - 1000),
    ?assertEqual({declined, thread_full},
                 spartan_mind:decide(Reply, gate(#{kind => peer, room => false}))).

the_reply_clock_has_a_default_and_a_knob_test() ->
    true = os:unsetenv("HECATE_MIND_REPLY_COOLDOWN_MS"),
    ?assert(spartan_mind:reply_cooldown_ms() >= 1000),
    ?assert(spartan_mind:reply_cooldown_ms() < 300_000),
    true = os:putenv("HECATE_MIND_REPLY_COOLDOWN_MS", "5000"),
    ?assertEqual(5000, spartan_mind:reply_cooldown_ms()),
    true = os:putenv("HECATE_MIND_REPLY_COOLDOWN_MS", "nonsense"),
    ?assert(spartan_mind:reply_cooldown_ms() >= 1000),
    true = os:unsetenv("HECATE_MIND_REPLY_COOLDOWN_MS").

%% --- holding a reply for later ---

the_newest_reply_per_story_is_kept_test() ->
    H1 = spartan_mind:hold(peer_post(<<"p1">>, <<"s1">>, ?NOW - 2000), #{}),
    H2 = spartan_mind:hold(peer_post(<<"p2">>, <<"s1">>, ?NOW - 1000), H1),
    H3 = spartan_mind:hold(peer_post(<<"p0">>, <<"s1">>, ?NOW - 9000), H2),
    ?assertEqual(1, map_size(H3)),
    ?assertMatch(#{<<"s1">> := #{post_id := <<"p2">>}}, H3).

stories_are_held_apart_test() ->
    H = spartan_mind:hold(peer_post(<<"p2">>, <<"s2">>, ?NOW),
                          spartan_mind:hold(peer_post(<<"p1">>, <<"s1">>, ?NOW), #{})),
    ?assertEqual(2, map_size(H)).

unprompted_speech_is_a_story_of_its_own_test() ->
    Unprompted = #{post_id => <<"u1">>, from => ?PEER, body => <<"a thought">>, posted_at => ?NOW},
    ?assertMatch(#{<<"u1">> := _}, spartan_mind:hold(Unprompted, #{})).

only_so_many_stories_are_held_and_the_oldest_goes_first_test() ->
    Posts = [peer_post(<<"p", (integer_to_binary(N))/binary>>, <<"s", (integer_to_binary(N))/binary>>,
                       ?NOW - 1000 * N) || N <- lists:seq(1, 12)],
    H = lists:foldl(fun spartan_mind:hold/2, #{}, Posts),
    ?assert(map_size(H) =< 8),
    ?assert(maps:is_key(<<"s1">>, H)),        %% the newest
    ?assertNot(maps:is_key(<<"s12">>, H)).    %% the oldest

the_newest_is_taken_up_first_test() ->
    H = lists:foldl(fun spartan_mind:hold/2, #{},
                    [peer_post(<<"p1">>, <<"s1">>, ?NOW - 3000),
                     peer_post(<<"p2">>, <<"s2">>, ?NOW - 1000),
                     peer_post(<<"p3">>, <<"s3">>, ?NOW - 2000)]),
    {Next, Rest, Expired} = spartan_mind:pop_held(H, ?NOW),
    ?assertMatch(#{post_id := <<"p2">>}, Next),
    ?assertEqual(2, map_size(Rest)),
    ?assertEqual([], Expired).

a_reply_held_too_long_is_let_go_not_answered_test() ->
    H = lists:foldl(fun spartan_mind:hold/2, #{},
                    [peer_post(<<"stale">>, <<"s1">>, ?NOW - 3_600_000),
                     peer_post(<<"fresh">>, <<"s2">>, ?NOW - 1000)]),
    {Next, Rest, Expired} = spartan_mind:pop_held(H, ?NOW),
    ?assertMatch(#{post_id := <<"fresh">>}, Next),
    ?assertEqual(0, map_size(Rest)),
    ?assertMatch([#{post_id := <<"stale">>}], Expired).

nothing_held_is_nothing_to_take_up_test() ->
    ?assertEqual({none, #{}, []}, spartan_mind:pop_held(#{}, ?NOW)).

%% --- a reply says which post it answers ---

a_spoken_reply_links_to_the_post_that_woke_the_mind_test() ->
    ?assertEqual(<<"p7">>, mind_tools:answering(<<>>, #{replying_to => <<"p7">>})),
    ?assertEqual(<<"p7">>, mind_tools:answering(undefined, #{replying_to => <<"p7">>})),
    ?assertEqual(<<"named">>, mind_tools:answering(<<"named">>, #{replying_to => <<"p7">>})),
    ?assertEqual(undefined, mind_tools:answering(<<>>, #{})).
