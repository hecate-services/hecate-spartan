%%% @doc Top supervisor for hecate_spartan.
%%%
%%% Walking skeleton: no children yet. Each vertical slice brings its own
%%% supervision when implemented (Phase 1a) — the registry projection, the
%%% route/broadcast desks, the entity-facing ingress listener, and the mesh
%%% receive drain. Slices own their own supervision; there is no central
%%% "all listeners" supervisor here. See plans/PLAN_HECATE_SPARTAN.md.
-module(hecate_spartan_sup).
-behaviour(supervisor).

-export([start_link/0, init/1]).

start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

init([]) ->
    SupFlags = #{strategy => one_for_one, intensity => 5, period => 10},
    Children = [
        %% Service issuer identity: owns the Ed25519 keypair, mints + verifies
        %% entity UCANs. Everything auth-bearing depends on it, so it starts
        %% first.
        worker(hecate_spartan_identity),

        %% Entity registry read model. Owns the `entities' ETS table; must
        %% start before the projection that writes into it.
        worker(hecate_spartan_entities),

        %% Projection: entity_registered_v1 -> entities registry.
        projection(entity_registered_v1_to_entities),

        %% Mesh-wide entity directory (local + announced peers). Must start
        %% before the announce PM and the federation registry that write it.
        worker(hecate_spartan_mesh_entities),

        %% PM: on entity_registered, announce to the federation (upsert local
        %% mesh_entities row + publish entity_announced fact).
        projection(on_entity_registered_announce),

        %% Federation registry: subscribe to spartan/registry, project peers'
        %% announcements into mesh_entities; re-announce local entities.
        worker(federation_registry),

        %% In-process message inbox. Must start before the message projection
        %% (which delivers into it) and before the ingress (which reads it).
        worker(hecate_spartan_inbox),

        %% Projection: message_routed_v1 -> recipient inbox.
        projection(message_routed_v1_to_inbox),

        %% Projection: message_broadcast_v1 -> every entity's inbox.
        projection(message_broadcast_v1_to_inboxes),

        %% Federation emitters (PMs): publish integration facts to the mesh so
        %% peer instances can deliver to entities homed there. Degrade safely
        %% while dark. Forward-compat until cross-relay PubSub is fixed.
        projection(on_message_routed_publish_fact),
        projection(on_message_broadcast_publish_fact),

        %% Entity-facing HTTP ingress + /health listener. Depends on identity
        %% (UCAN minting), the registry, and the inbox, so it starts last.
        worker(hecate_spartan_ingress)
    ],
    {ok, {SupFlags, Children}}.

projection(Module) ->
    #{id => Module,
      start => {evoq_projection, start_link,
                [Module, #{}, #{store_id => hecate_spartan_store}]},
      restart => permanent, shutdown => 5000, type => worker,
      modules => [Module]}.

worker(Module) ->
    #{id => Module,
      start => {Module, start_link, []},
      restart => permanent,
      shutdown => 5000,
      type => worker,
      modules => [Module]}.
