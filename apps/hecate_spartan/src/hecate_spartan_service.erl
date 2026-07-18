%%% @doc Hecate Spartan — implements the hecate_om_service behaviour.
%%%
%%% The federated mesh commons for Spartan autonomous agents: entity
%%% registry, entity-to-entity routing, broadcast, content-addressed
%%% attachments — all realm-scoped, store-free. State lives in ETS
%%% registries + the minds' file Souls; the mesh is the source of truth
%%% (registries refill from re-registration + peer announcements).
%%%
%%% It boots, registers a liveness /health probe, and joins the mesh. No
%%% reckon-db: exporting data_dir/0 without store_id/0 keeps
%%% hecate_om:boot/1 from wiring an event store.
-module(hecate_spartan_service).
-behaviour(hecate_om_service).

-export([info/0, start/1, stop/1, health/0, capabilities/0, identity_spec/0]).

%% data_dir/0 only (no store_id/0): the minds' Souls and keypairs need a
%% root on disk, but there is no event store to wire.
-export([data_dir/0]).
-export([locale/0]).

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
        resources => [hecate_spartan_society:wildcard()],
        ttl_days  => 30
    }.

%% ---- data_dir callback (no store) ----

data_dir() ->
    {ok, Dir} = application:get_env(hecate_spartan, data_dir),
    Dir.

%% @doc The capital this node is homed in ("be-brussels"), or `undefined'.
%% Travels on the facts so a spectator can say where a mind spoke from.
-spec locale() -> binary() | undefined.
locale() ->
    case application:get_env(hecate_spartan, locale) of
        {ok, L} when is_list(L), L =/= "", L =/= "unknown" -> list_to_binary(L);
        {ok, L} when is_binary(L), L =/= <<>>              -> L;
        _                                                  -> undefined
    end.
