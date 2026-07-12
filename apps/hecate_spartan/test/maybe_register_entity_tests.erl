%%% @doc Tests for the register_entity command handler (pure domain).
-module(maybe_register_entity_tests).
-include_lib("eunit/include/eunit.hrl").

-define(PUBKEY32, <<0:256>>).  %% a syntactically valid 32-byte Ed25519 key

valid_registration_emits_event_test() ->
    Payload = #{entity_name => <<"Alpha">>,
                did => <<"did:key:alpha">>,
                pubkey => ?PUBKEY32,
                registered_at => 1720000000000},
    {ok, [Event]} = maybe_register_entity:handle_from_map(Payload),
    ?assertEqual(<<"entity_registered_v1">>, maps:get(event_type, Event)),
    ?assertEqual(<<"Alpha">>, maps:get(entity_name, Event)),
    ?assertEqual(<<"did:key:alpha">>, maps:get(did, Event)).

registered_at_defaults_when_absent_test() ->
    Payload = #{entity_name => <<"Alpha">>,
                did => <<"did:key:alpha">>,
                pubkey => ?PUBKEY32},
    {ok, [Event]} = maybe_register_entity:handle_from_map(Payload),
    ?assert(is_integer(maps:get(registered_at, Event))).

rejects_empty_name_test() ->
    Payload = #{entity_name => <<>>,
                did => <<"did:key:alpha">>,
                pubkey => ?PUBKEY32,
                registered_at => 1},
    ?assertEqual({error, entity_name_required},
                 maybe_register_entity:handle_from_map(Payload)).

rejects_bad_pubkey_length_test() ->
    Payload = #{entity_name => <<"Alpha">>,
                did => <<"did:key:alpha">>,
                pubkey => <<"too-short">>,
                registered_at => 1},
    ?assertEqual({error, invalid_pubkey},
                 maybe_register_entity:handle_from_map(Payload)).

rejects_missing_fields_test() ->
    ?assertEqual({error, missing_fields},
                 maybe_register_entity:handle_from_map(#{entity_name => <<"A">>})).
