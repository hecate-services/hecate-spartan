%%% @doc Tests for the pre-LLM engagement gate that lets a society converse
%%% without spiralling into a token-burn loop: a mind ignores its own speech,
%%% opens a story at most once per cooldown, and answers a peer on its own,
%%% shorter clock. This is the cheap decision made BEFORE any LLM call, so it
%%% is worth guarding directly.
-module(mind_engagement_tests).

-include_lib("eunit/include/eunit.hrl").

-define(ME, <<"did:macula:spartan:ME">>).
-define(OTHER, <<"did:macula:spartan:OTHER">>).
-define(COOLDOWN, 15000).
-define(REPLY_COOLDOWN, 1000).
-define(NOW, 100000).

post(From, Body) -> #{from => From, body => Body, post_id => <<"p1">>, posted_at => ?NOW - 5}.

gate(Over) ->
    maps:merge(#{kind => peer, now => ?NOW, last_opened => 0, last_replied => 0,
                 cooldown => ?COOLDOWN, reply_cooldown => ?REPLY_COOLDOWN, room => true},
               Over).

%% A peer's post, when the mind is off its reply clock, is worth reasoning about.
peer_speech_engages_test() ->
    Fact = post(?OTHER, <<"what makes a promise trustworthy?">>),
    ?assertEqual({ok, <<"what makes a promise trustworthy?">>},
                 spartan_mind:decide(Fact, gate(#{kind => peer}))).

%% A mind never reacts to its own speech (it hears the agora, where its own
%% posts return). This is the loop's first line of defence.
own_speech_is_ignored_test() ->
    Fact = post(?ME, <<"i just said this">>),
    ?assertEqual({declined, own_speech},
                 spartan_mind:decide(Fact, gate(#{kind => own}))).

%% History said again is never reasoned about, whatever the clocks say.
history_is_ignored_test() ->
    Fact = post(?OTHER, <<"i said this an hour ago">>),
    ?assertEqual({declined, replay},
                 spartan_mind:decide(Fact, gate(#{kind => replay}))).

%% Within the cooldown window an OPENING is skipped: the mind opens a story
%% at most once per cooldown, so a busy feed cannot burn tokens without bound.
cooldown_suppresses_reopening_test() ->
    Fact = #{from => <<"hecate-news">>, body => <<"[NEWS] something">>, item_id => <<"s1">>},
    Recent = ?NOW - 5000,   %% opened 5s ago, cooldown is 15s
    ?assertEqual({declined, cooldown},
                 spartan_mind:decide(Fact, gate(#{kind => opening, last_opened => Recent}))).

%% Once the cooldown elapses, the next opening engages again.
cooldown_elapsed_reopens_test() ->
    Fact = #{from => <<"hecate-news">>, body => <<"[NEWS] still there?">>, item_id => <<"s2">>},
    Old = ?NOW - 20000,     %% opened 20s ago, past the 15s cooldown
    ?assertEqual({ok, <<"[NEWS] still there?">>},
                 spartan_mind:decide(Fact, gate(#{kind => opening, last_opened => Old}))).

%% A bodyless or empty stimulus is nothing to reason about.
empty_body_is_skipped_test() ->
    ?assertEqual({declined, empty},
                 spartan_mind:decide(#{from => ?OTHER}, gate(#{}))),
    ?assertEqual({declined, empty},
                 spartan_mind:decide(post(?OTHER, <<>>), gate(#{}))).

%% A broadcast (e.g. a sentinel digest) has no `from', so it is never mistaken
%% for the mind's own speech and engages on the opening clock.
broadcast_without_from_engages_test() ->
    Fact = #{body => <<"sector 4 anomaly digest">>},
    ?assertEqual({ok, <<"sector 4 anomaly digest">>},
                 spartan_mind:decide(Fact, gate(#{kind => other}))).
