%%% @doc Tests for the entity registry read model (store-free: the handler writes
%%% the row through hecate_spartan_entities:upsert/2).
-module(entity_registry_tests).
-include_lib("eunit/include/eunit.hrl").

registry_test_() ->
    {setup, fun setup/0, fun cleanup/1,
     fun(_) ->
         [ handler_upserts_entity()
         , registry_lookup_and_count()
         , unknown_entity_is_not_found()
         ]
     end}.

setup() ->
    {ok, Pid} = hecate_spartan_entities:start_link(),
    %% One registration lands in the table exactly as dispatch does it.
    {Did, Entry} = maybe_register_entity:row(
                     #{did => <<"did:key:alpha">>,
                       entity_name => <<"Alpha">>,
                       pubkey => <<0:256>>,
                       registered_at => 1720000000000}),
    ok = hecate_spartan_entities:upsert(Did, Entry),
    #{pid => Pid}.

cleanup(#{pid := Pid}) ->
    gen_server:stop(Pid),
    ok.

handler_upserts_entity() ->
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
