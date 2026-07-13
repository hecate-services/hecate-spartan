%%% @doc Tests for rebuilding the in-memory registries from the event log.
%%%
%%% The registries are ETS, so they die with the node. The events do not. On
%%% boot each table owner replays entity_registered_v1 and rebuilds itself —
%%% otherwise a node restart silently un-registers every entity homed on it.
-module(registry_rebuild_tests).
-include_lib("eunit/include/eunit.hrl").

%% A replayed event comes back FLATTENED (business fields merged into the
%% envelope), not nested under `data' like a live projection event. The row
%% builder has to read both shapes — this pins the flattened one.
row_from_replayed_event_test() ->
    Replayed = #{event_type => <<"entity_registered_v1">>,
                 event_id => <<"e1">>,
                 stream_id => <<"entity-0123456789abcdef0123456789abcdef">>,
                 version => 0,
                 did => <<"did:key:zeta">>,
                 entity_name => <<"Zeta">>,
                 pubkey => <<0:256>>,
                 registered_at => 1720000000000},
    {Did, Entry} = entity_registered_v1_to_entities:row(Replayed),
    ?assertEqual(<<"did:key:zeta">>, Did),
    ?assertEqual(<<"Zeta">>, maps:get(entity_name, Entry)),
    ?assertEqual(1, maps:get(status, Entry)),
    ?assertEqual(1720000000000, maps:get(registered_at, Entry)).

%% Binary keys survive the reckon-db round-trip on some paths; row/1 accepts them.
row_accepts_binary_keys_test() ->
    Replayed = #{<<"did">> => <<"did:key:eta">>,
                 <<"entity_name">> => <<"Eta">>,
                 <<"pubkey">> => <<0:256>>,
                 <<"registered_at">> => 42},
    {Did, Entry} = entity_registered_v1_to_entities:row(Replayed),
    ?assertEqual(<<"did:key:eta">>, Did),
    ?assertEqual(<<"Eta">>, maps:get(entity_name, Entry)).

%% With no store configured (unit test env), replay is empty rather than a crash
%% — the table owners must still boot.
replay_without_store_is_empty_test() ->
    ok = application:unset_env(hecate_spartan, event_store_id),
    ?assertEqual([], entity_registered_v1:replay()).

%% Both table owners boot on an unreadable store and come up empty, not dead.
owners_boot_without_store_test() ->
    ok = application:unset_env(hecate_spartan, event_store_id),
    {ok, EPid} = hecate_spartan_entities:start_link(),
    {ok, MPid} = hecate_spartan_mesh_entities:start_link(),
    ?assertEqual(0, hecate_spartan_entities:count()),
    ?assertEqual(0, hecate_spartan_mesh_entities:count()),
    gen_server:stop(MPid),
    gen_server:stop(EPid).

%% An entity that lost its keypair comes back under the same name with a new
%% DID. The directory must resolve that name to the LIVE entity: the newest
%% registration takes the name, the superseded DID leaves the directory.
newest_claim_takes_the_name_test() ->
    ok = application:unset_env(hecate_spartan, event_store_id),
    {ok, Pid} = hecate_spartan_mesh_entities:start_link(),
    ok = hecate_spartan_mesh_entities:upsert(
           #{did => <<"did:key:old">>, entity_name => <<"Axiom">>,
             home => <<"did:key:node">>, registered_at => 100}),
    ok = hecate_spartan_mesh_entities:upsert(
           #{did => <<"did:key:new">>, entity_name => <<"Axiom">>,
             home => <<"did:key:node">>, registered_at => 200}),
    ?assertEqual(1, hecate_spartan_mesh_entities:count()),
    ?assertMatch({ok, _}, hecate_spartan_mesh_entities:get(<<"did:key:new">>)),
    ?assertEqual({error, not_found},
                 hecate_spartan_mesh_entities:get(<<"did:key:old">>)),
    gen_server:stop(Pid).

%% Replay order is not guaranteed to be luckiest-last: a stale claim arriving
%% after the live one (an old peer re-announcing, say) must not unseat it.
stale_claim_does_not_unseat_test() ->
    ok = application:unset_env(hecate_spartan, event_store_id),
    {ok, Pid} = hecate_spartan_mesh_entities:start_link(),
    ok = hecate_spartan_mesh_entities:upsert(
           #{did => <<"did:key:live">>, entity_name => <<"Axiom">>,
             home => <<"did:key:node">>, registered_at => 200}),
    ok = hecate_spartan_mesh_entities:upsert(
           #{did => <<"did:key:zombie">>, entity_name => <<"Axiom">>,
             home => <<"did:key:node">>, registered_at => 100}),
    ?assertEqual(1, hecate_spartan_mesh_entities:count()),
    ?assertMatch({ok, _}, hecate_spartan_mesh_entities:get(<<"did:key:live">>)),
    gen_server:stop(Pid).

%% Different names coexist — superseding is per-name, not a global truncation.
distinct_names_coexist_test() ->
    ok = application:unset_env(hecate_spartan, event_store_id),
    {ok, Pid} = hecate_spartan_mesh_entities:start_link(),
    ok = hecate_spartan_mesh_entities:upsert(
           #{did => <<"did:key:a">>, entity_name => <<"erasmus">>,
             home => <<"did:key:be">>, registered_at => 100}),
    ok = hecate_spartan_mesh_entities:upsert(
           #{did => <<"did:key:b">>, entity_name => <<"leibniz">>,
             home => <<"did:key:de">>, registered_at => 100}),
    ?assertEqual(2, hecate_spartan_mesh_entities:count()),
    gen_server:stop(Pid).
