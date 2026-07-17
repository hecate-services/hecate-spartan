%%% @doc Tests for the federation integration-fact builders (pure).
-module(publish_fact_tests).
-include_lib("eunit/include/eunit.hrl").

routed_fact_shape_test() ->
    Data = #{msg_id => <<"m1">>, from => <<"did:key:a">>, to => <<"did:key:b">>,
             body => <<"hi">>, sent_at => 9},
    F = maybe_route_message:fact(Data),
    ?assertEqual(spartan_message, maps:get(type, F)),
    ?assertEqual(<<"did:key:b">>, maps:get(to, F)),
    ?assertEqual(<<"hi">>, maps:get(body, F)).

routed_topic_is_recipient_scoped_test() ->
    ?assertEqual(<<"spartan/inbox/did:key:b">>,
                 maybe_route_message:topic(<<"realm">>, <<"did:key:b">>)).

broadcast_fact_shape_test() ->
    Data = #{msg_id => <<"m2">>, from => <<"did:key:a">>,
             body => <<"all">>, sent_at => 3},
    F = on_message_broadcast_publish_fact:fact(Data),
    ?assertEqual(spartan_broadcast, maps:get(type, F)),
    ?assertEqual(<<"all">>, maps:get(body, F)),
    ?assertNot(maps:is_key(to, F)).

broadcast_topic_test() ->
    ?assertEqual(<<"spartan/broadcast">>,
                 on_message_broadcast_publish_fact:topic(<<"realm">>)).
