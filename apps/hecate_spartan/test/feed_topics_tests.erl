%%% @doc Tests for a mind's configured feed subscription
%%% (spartan_mind:feed_topics/0): the firehose by default, or specific
%%% category sub-topics (HECATE_MIND_FEED_TOPICS) for real informational
%%% asymmetry between minds instead of everyone hearing everything.
-module(feed_topics_tests).

-include_lib("eunit/include/eunit.hrl").

unset_env_hears_the_firehose_test() ->
    with_unset("HECATE_MIND_FEED_TOPICS", fun() ->
        ?assertEqual([<<"spartan/feed">>], spartan_mind:feed_topics())
    end).

empty_env_hears_the_firehose_test() ->
    with_env("HECATE_MIND_FEED_TOPICS", "", fun() ->
        ?assertEqual([<<"spartan/feed">>], spartan_mind:feed_topics())
    end).

one_axis_subscribes_to_one_sub_topic_test() ->
    with_env("HECATE_MIND_FEED_TOPICS", "country:de", fun() ->
        ?assertEqual([<<"spartan/feed/country/de">>], spartan_mind:feed_topics())
    end).

%% Combining axes WIDENS the diet (a separate topic per clause, union
%% semantics) — it does not narrow it to their intersection.
multiple_axes_subscribe_to_multiple_sub_topics_test() ->
    with_env("HECATE_MIND_FEED_TOPICS", "source_type:wire,topic_class:economy", fun() ->
        Topics = spartan_mind:feed_topics(),
        ?assertEqual(2, length(Topics)),
        ?assert(lists:member(<<"spartan/feed/source_type/wire">>, Topics)),
        ?assert(lists:member(<<"spartan/feed/topic_class/economy">>, Topics))
    end).

%% A repeated axis with different values is exactly the union-widening
%% within one axis, no special-casing needed.
repeated_axis_subscribes_to_both_values_test() ->
    with_env("HECATE_MIND_FEED_TOPICS", "country:de,country:at", fun() ->
        Topics = spartan_mind:feed_topics(),
        ?assertEqual(2, length(Topics)),
        ?assert(lists:member(<<"spartan/feed/country/de">>, Topics)),
        ?assert(lists:member(<<"spartan/feed/country/at">>, Topics))
    end).

%% An unknown axis name is a config typo, not a topic — dropped rather than
%% subscribed to blindly. A malformed clause (no ':') is dropped the same way.
unknown_axis_and_malformed_clauses_are_dropped_test() ->
    with_env("HECATE_MIND_FEED_TOPICS", "region:eu,country:de,justtext", fun() ->
        ?assertEqual([<<"spartan/feed/country/de">>], spartan_mind:feed_topics())
    end).

%% Whitespace around a clause or its parts is tolerated (a hand-edited env
%% file is exactly where stray spaces creep in).
whitespace_is_trimmed_test() ->
    with_env("HECATE_MIND_FEED_TOPICS", " country : de , topic_class:science ", fun() ->
        Topics = spartan_mind:feed_topics(),
        ?assert(lists:member(<<"spartan/feed/country/de">>, Topics)),
        ?assert(lists:member(<<"spartan/feed/topic_class/science">>, Topics))
    end).

%% --- env fixtures (restore whatever was there) ---

with_env(Var, Value, Fun) ->
    Prev = os:getenv(Var),
    os:putenv(Var, Value),
    try Fun() after restore(Var, Prev) end.

with_unset(Var, Fun) ->
    Prev = os:getenv(Var),
    os:unsetenv(Var),
    try Fun() after restore(Var, Prev) end.

restore(Var, false) -> os:unsetenv(Var);
restore(Var, Value) -> os:putenv(Var, Value).
