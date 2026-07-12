%%% @doc Tests for the entity registry read model + its projection.
-module(entity_registry_tests).
-include_lib("eunit/include/eunit.hrl").

registry_test_() ->
    {setup, fun setup/0, fun cleanup/1,
     fun(_) ->
         [ projection_upserts_entity()
         , registry_lookup_and_count()
         , unknown_entity_is_not_found()
         ]
     end}.

setup() ->
    {ok, Pid} = hecate_spartan_entities:start_link(),
    {ok, _State, RM} = entity_registered_v1_to_entities:init(#{}),
    %% Project one registration into the table.
    Event = #{event_type => <<"entity_registered_v1">>,
              data => #{did => <<"did:key:alpha">>,
                        entity_name => <<"Alpha">>,
                        pubkey => <<0:256>>,
                        registered_at => 1720000000000}},
    {ok, _S2, _RM2} = entity_registered_v1_to_entities:project(Event, #{}, #{}, RM),
    #{pid => Pid}.

cleanup(#{pid := Pid}) ->
    gen_server:stop(Pid),
    ok.

projection_upserts_entity() ->
    {ok, Entry} = hecate_spartan_entities:get(<<"did:key:alpha">>),
    [ ?_assertEqual(<<"Alpha">>, maps:get(entity_name, Entry))
    , ?_assertEqual(<<"did:key:alpha">>, maps:get(did, Entry))
    , ?_assertEqual(1, maps:get(status, Entry)) ].

registry_lookup_and_count() ->
    All = hecate_spartan_entities:all(),
    [ ?_assertEqual(1, hecate_spartan_entities:count())
    , ?_assertEqual(1, length(All)) ].

unknown_entity_is_not_found() ->
    ?_assertEqual({error, not_found},
                  hecate_spartan_entities:get(<<"did:key:ghost">>)).
