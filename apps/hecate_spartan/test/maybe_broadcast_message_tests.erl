%%% @doc Tests for the broadcast_message handler + fan-out projection.
-module(maybe_broadcast_message_tests).
-include_lib("eunit/include/eunit.hrl").

valid_broadcast_emits_event_test() ->
    P = #{msg_id => <<"m1">>, from => <<"did:key:a">>,
          body => <<"all hands">>, sent_at => 7},
    {ok, [E]} = maybe_broadcast_message:handle_from_map(P),
    ?assertEqual(<<"message_broadcast_v1">>, maps:get(event_type, E)),
    ?assertEqual(<<"all hands">>, maps:get(body, E)).

empty_body_rejected_test() ->
    P = #{msg_id => <<"m1">>, from => <<"did:key:a">>, body => <<>>, sent_at => 1},
    ?assertEqual({error, empty_body}, maybe_broadcast_message:handle_from_map(P)).

missing_fields_rejected_test() ->
    ?assertEqual({error, missing_fields},
                 maybe_broadcast_message:handle_from_map(#{from => <<"a">>})).

fanout_delivers_to_all_but_sender_test() ->
    {ok, EPid} = hecate_spartan_entities:start_link(),
    {ok, IPid} = hecate_spartan_inbox:start_link(),
    _ = [ets:insert(entities, {D, #{did => D}})
         || D <- [<<"did:key:a">>, <<"did:key:b">>, <<"did:key:c">>]],

    {ok, _S, RM} = message_broadcast_v1_to_inboxes:init(#{}),
    Event = #{event_type => <<"message_broadcast_v1">>,
              data => #{msg_id => <<"m1">>, from => <<"did:key:a">>,
                        body => <<"all hands">>, sent_at => 1}},
    {ok, _S2, _RM2} = message_broadcast_v1_to_inboxes:project(Event, #{}, #{}, RM),
    timer:sleep(50),

    ?assertEqual(1, length(hecate_spartan_inbox:pending(<<"did:key:b">>))),
    ?assertEqual(1, length(hecate_spartan_inbox:pending(<<"did:key:c">>))),
    ?assertEqual(0, length(hecate_spartan_inbox:pending(<<"did:key:a">>))),

    gen_server:stop(IPid),
    gen_server:stop(EPid).
