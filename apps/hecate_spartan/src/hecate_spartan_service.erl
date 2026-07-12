%%% @doc Hecate Spartan — implements the hecate_om_service behaviour.
%%%
%%% The federated mesh commons for Spartan autonomous agents: entity
%%% registry, entity-to-entity routing, broadcast, content-addressed
%%% attachments — all realm-scoped, all recorded as reckon-db events so
%%% delivery carries provenance (and right-to-erasure) for free.
%%%
%%% This is the walking skeleton. It boots, wires its store, registers a
%%% liveness /health probe, and joins the mesh. The business capabilities
%%% and their vertical slices land in Phase 1a — see
%%% plans/PLAN_HECATE_SPARTAN.md for the desk-by-desk roadmap.
-module(hecate_spartan_service).
-behaviour(hecate_om_service).

-export([info/0, start/1, stop/1, health/0, capabilities/0, identity_spec/0]).

%% Store-backed: hecate_om:boot/1 auto-starts the reckon-db store and its
%% evoq subscription before start/1 fires.
-export([store_id/0, data_dir/0, store_indexes/0]).

info() ->
    #{
        name        => <<"hecate-spartan">>,
        version     => <<"0.1.0">>,
        description => <<"Federated mesh commons for Spartan autonomous agents">>
    }.

start(_Opts) ->
    hecate_spartan_sup:start_link().

stop(_State) ->
    ok.

%% Liveness probe. Boots green once the supervision tree is up. Slices
%% refine this to a real readiness check (store reachable, mesh linked)
%% as they land.
health() ->
    ok.

%% Nothing advertised on the mesh until the desks that back each capability
%% exist. The target set (spartan.register_entity, spartan.route_message,
%% spartan.broadcast, spartan.share_artifact, spartan.fetch_artifact,
%% spartan.discover, spartan.receive) is defined in
%% plans/PLAN_HECATE_SPARTAN.md and advertised slice-by-slice as it ships.
capabilities() ->
    [].

%% The UCAN this service asks hecate-realm to mint: authority to route and
%% broadcast on spartan topics and to advertise entity presence.
identity_spec() ->
    #{
        scope     => <<"spartan">>,
        actions   => [<<"route">>, <<"broadcast">>, <<"advertise_entity">>],
        resources => [<<"spartan/*">>],
        ttl_days  => 30
    }.

%% ---- store callbacks ----

store_id() ->
    {ok, Id} = application:get_env(hecate_spartan, event_store_id),
    Id.

data_dir() ->
    {ok, Dir} = application:get_env(hecate_spartan, data_dir),
    Dir.

%% Secondary indexes for entity-scoped queries: which entity a fact concerns,
%% and a composite (realm, entity) hash for direct-inbox lookups. Payload
%% indexes are how reckon-db CCC queries find messages without a full scan.
store_indexes() ->
    [
        event_type,
        {payload, <<"entity">>},
        {payload_hash, [<<"realm">>, <<"entity">>]}
    ].
