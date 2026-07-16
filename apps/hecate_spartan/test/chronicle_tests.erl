%%% @doc Tests for the event-sourced chronicle: a turn becomes a lean
%%% turn_taken_v1 event that preserves what was heard, thought, and done, plus
%%% its token cost. The store-backed replay is exercised by integration; here we
%%% cover the pure command-to-event path.
-module(chronicle_tests).

-include_lib("eunit/include/eunit.hrl").

turn_params() ->
    #{turn_id => <<"deadbeefdeadbeefdeadbeefdeadbeef">>,
      did => <<"did:macula:spartan:AB">>,
      heard => <<"is anyone watching sector 4?">>,
      thought => <<"nothing actionable; staying quiet">>,
      actions => [<<"reflect">>],
      tokens => 812}.

turn_becomes_a_lean_event_test() ->
    {ok, [Event]} = maybe_record_turn:handle_from_map(turn_params()),
    ?assertEqual(<<"turn_taken_v1">>, maps:get(event_type, Event)),
    ?assertEqual(<<"is anyone watching sector 4?">>, maps:get(heard, Event)),
    ?assertEqual([<<"reflect">>], maps:get(actions, Event)),
    ?assertEqual(812, maps:get(tokens, Event)),
    %% the event carries no assembled context, only the lean fields
    ?assertEqual(lists:sort([event_type, turn_id, did, heard, thought,
                             actions, tokens, at]),
                 lists:sort(maps:keys(Event))).

silent_turn_is_still_recorded_test() ->
    Params = (turn_params())#{actions => [], thought => <<>>},
    {ok, [Event]} = maybe_record_turn:handle_from_map(Params),
    ?assertEqual([], maps:get(actions, Event)),
    ?assertEqual(<<>>, maps:get(thought, Event)).

missing_identity_is_rejected_test() ->
    ?assertMatch({error, _}, record_turn_v1:new(#{heard => <<"x">>})),
    ?assertEqual({error, missing_fields},
                 maybe_record_turn:handle_from_map(#{heard => <<"x">>})).

event_round_trips_test() ->
    Event = turn_taken_v1:new(turn_params()),
    Map = turn_taken_v1:to_map(Event),
    {ok, Back} = turn_taken_v1:from_map(Map),
    ?assertEqual(Map, turn_taken_v1:to_map(Back)).
