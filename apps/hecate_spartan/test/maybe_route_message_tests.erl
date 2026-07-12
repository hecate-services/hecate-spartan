%%% @doc Tests for the route_message command handler (pure domain).
-module(maybe_route_message_tests).
-include_lib("eunit/include/eunit.hrl").

valid_route_emits_event_test() ->
    P = #{msg_id => <<"abcd">>, from => <<"did:key:a">>,
          to => <<"did:key:b">>, body => <<"hello">>, sent_at => 42},
    {ok, [Event]} = maybe_route_message:handle_from_map(P),
    ?assertEqual(<<"message_routed_v1">>, maps:get(event_type, Event)),
    ?assertEqual(<<"did:key:b">>, maps:get(to, Event)),
    ?assertEqual(<<"hello">>, maps:get(body, Event)).

empty_body_rejected_test() ->
    P = #{msg_id => <<"abcd">>, from => <<"did:key:a">>,
          to => <<"did:key:b">>, body => <<>>, sent_at => 1},
    ?assertEqual({error, empty_body}, maybe_route_message:handle_from_map(P)).

missing_to_rejected_test() ->
    P = #{msg_id => <<"abcd">>, from => <<"did:key:a">>,
          to => <<>>, body => <<"hi">>, sent_at => 1},
    ?assertEqual({error, to_required}, maybe_route_message:handle_from_map(P)).

missing_fields_rejected_test() ->
    ?assertEqual({error, missing_fields},
                 maybe_route_message:handle_from_map(#{from => <<"a">>})).
