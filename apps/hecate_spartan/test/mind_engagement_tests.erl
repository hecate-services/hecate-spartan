%%% @doc Tests for the pre-LLM engagement gate that lets a society converse
%%% without spiralling into a token-burn loop: a mind ignores its own speech and
%%% reasons at most once per cooldown. This is the cheap decision made BEFORE any
%%% Melious call, so it is worth guarding directly.
-module(mind_engagement_tests).

-include_lib("eunit/include/eunit.hrl").

-define(ME, <<"did:macula:spartan:ME">>).
-define(OTHER, <<"did:macula:spartan:OTHER">>).
-define(COOLDOWN, 15000).

post(From, Body) -> #{from => From, body => Body}.

%% A peer's post, when the mind is off cooldown, is worth reasoning about.
peer_speech_engages_test() ->
    Fact = post(?OTHER, <<"what makes a promise trustworthy?">>),
    ?assertEqual({ok, <<"what makes a promise trustworthy?">>},
                 spartan_mind:decide(Fact, ?ME, 0, 100000, ?COOLDOWN)).

%% A mind never reacts to its own speech (it hears the agora, where its own
%% posts return). This is the loop's first line of defence.
own_speech_is_ignored_test() ->
    Fact = post(?ME, <<"i just said this">>),
    ?assertEqual(skip, spartan_mind:decide(Fact, ?ME, 0, 100000, ?COOLDOWN)).

%% Within the cooldown window, even a peer's post is skipped: the mind reasons
%% at most once per cooldown, so a busy square cannot burn tokens without bound.
cooldown_suppresses_reengagement_test() ->
    Fact = post(?OTHER, <<"reply to me now">>),
    Now = 100000,
    Recent = Now - 5000,   %% reasoned 5s ago, cooldown is 15s
    ?assertEqual(skip, spartan_mind:decide(Fact, ?ME, Recent, Now, ?COOLDOWN)).

%% Once the cooldown elapses, the same peer post engages again.
cooldown_elapsed_reengages_test() ->
    Fact = post(?OTHER, <<"still there?">>),
    Now = 100000,
    Old = Now - 20000,     %% reasoned 20s ago, past the 15s cooldown
    ?assertEqual({ok, <<"still there?">>},
                 spartan_mind:decide(Fact, ?ME, Old, Now, ?COOLDOWN)).

%% A bodyless or empty stimulus is nothing to reason about.
empty_body_is_skipped_test() ->
    ?assertEqual(skip, spartan_mind:decide(#{from => ?OTHER}, ?ME, 0, 100000, ?COOLDOWN)),
    ?assertEqual(skip, spartan_mind:decide(post(?OTHER, <<>>), ?ME, 0, 100000, ?COOLDOWN)).

%% A broadcast (e.g. a sentinel digest) has no `from', so it is never mistaken
%% for the mind's own speech and engages normally.
broadcast_without_from_engages_test() ->
    Fact = #{body => <<"sector 4 anomaly digest">>},
    ?assertEqual({ok, <<"sector 4 anomaly digest">>},
                 spartan_mind:decide(Fact, ?ME, 0, 100000, ?COOLDOWN)).
