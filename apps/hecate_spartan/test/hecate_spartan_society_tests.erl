%%% @doc A society is a topic namespace. These pin that a second use case is a
%%% config change (HECATE_SOCIETY), not a code change.
-module(hecate_spartan_society_tests).
-include_lib("eunit/include/eunit.hrl").

defaults_to_spartan_test() ->
    with_unset("HECATE_SOCIETY", fun() ->
        ?assertEqual(<<"spartan">>, hecate_spartan_society:namespace()),
        ?assertEqual(<<"spartan/agora">>, hecate_spartan_society:agora()),
        ?assertEqual(<<"spartan/feed">>, hecate_spartan_society:feed()),
        ?assertEqual(<<"spartan/registry">>, hecate_spartan_society:topic(<<"registry">>))
    end).

env_places_the_node_in_another_society_test() ->
    with_env("HECATE_SOCIETY", "news", fun() ->
        ?assertEqual(<<"news">>, hecate_spartan_society:namespace()),
        ?assertEqual(<<"news/agora">>, hecate_spartan_society:agora()),
        ?assertEqual(<<"news/feed">>, hecate_spartan_society:feed()),
        ?assertEqual(<<"news/broadcast">>, hecate_spartan_society:topic(<<"broadcast">>))
    end).

derived_topics_test() ->
    with_env("HECATE_SOCIETY", "news", fun() ->
        ?assertEqual(<<"news/inbox/did:key:a">>,
                     hecate_spartan_society:inbox(<<"did:key:a">>)),
        ?assertEqual(<<"news/committee/c1">>,
                     hecate_spartan_society:committee(<<"c1">>)),
        ?assertEqual(<<"news/io.macula/agora">>,
                     hecate_spartan_society:cap_resource(<<"io.macula">>, <<"agora">>)),
        ?assertEqual(<<"news/*">>, hecate_spartan_society:wildcard())
    end).

%% Every mesh-facing topic function agrees with the society namespace, so a
%% node's minds and its capabilities all speak the same use case.
capability_slices_follow_the_society_test() ->
    with_env("HECATE_SOCIETY", "news", fun() ->
        ?assertEqual(<<"news/agora">>, maybe_publish_to_agora:topic()),
        ?assertEqual(<<"news/registry">>, maybe_register_entity:topic()),
        ?assertEqual(<<"news/activity">>, maybe_report_activity:topic()),
        ?assertEqual(<<"news/broadcast">>, maybe_broadcast_message:topic(<<"realm">>)),
        ?assertEqual(<<"news/inbox/did:key:b">>,
                     maybe_route_message:topic(<<"realm">>, <<"did:key:b">>))
    end).

%% --- env fixtures ---

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
