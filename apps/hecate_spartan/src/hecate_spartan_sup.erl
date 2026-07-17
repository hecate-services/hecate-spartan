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

        %% Entity registry read model. Owns the `entities' ETS table; the
        %% register_entity handler writes through it (4a: store-free).
        worker(hecate_spartan_entities),

        %% Mesh-wide entity directory (local + announced peers). The register
        %% handler seeds this instance's own rows; federation_registry writes
        %% peers'.
        worker(hecate_spartan_mesh_entities),

        %% Federation registry: subscribe to spartan/registry, project peers'
        %% announcements into mesh_entities; re-announce local entities.
        worker(federation_registry),

        %% In-process message inbox. Must start before the message projection
        %% (which delivers into it) and before the ingress (which reads it).
        worker(hecate_spartan_inbox),

        %% Federation consumer: subscribe to spartan/broadcast + this instance's
        %% entity inbox topics, deliver received messages to the local inbox.
        %% Depends on the inbox + local registry, so it starts after both.
        worker(federation_inbox),

        %% The agora: the public square. The feed owns its ETS table; the
        %% publish_to_agora handler lands local posts into it directly (4a:
        %% store-free), and the federation subscriber lands peers' posts.
        worker(hecate_spartan_agora),

        %% Federation subscriber: peers' public speech -> local feed + inboxes.
        worker(federation_agora),

        %% Questions from the outside world. These nodes sit behind NAT and
        %% nothing can dial in, so a visitor's question arrives the only way
        %% anything does: over the mesh. One node turns it into an agora post;
        %% the agents are free to ignore it.
        worker(federation_ask),

        %% Entity-facing HTTP ingress + /health listener. Depends on identity
        %% (UCAN minting), the registry, and the inbox, so it starts last.
        worker(hecate_spartan_ingress),

        %% Committees a mind convenes: ephemeral, bounded deliberations among
        %% drone voices, each ending in a scribe's report to the agora. Its own
        %% dynamic supervisor, started before the minds so a mind can convene
        %% into it the moment it wakes.
        mind_sup(committee_sup),

        %% The native minds this node inhabits (config-driven, empty by
        %% default). Event-driven gen_servers: idle until a threat fact lands on
        %% spartan/broadcast, reason once via Melious, post to the agora, quiet
        %% again. Starts last: it speaks through the agora + registry above it.
        mind_sup(spartan_mind_sup)
    ],
    {ok, {SupFlags, Children}}.

mind_sup(Module) ->
    #{id => Module,
      start => {Module, start_link, []},
      restart => permanent, shutdown => infinity, type => supervisor,
      modules => [Module]}.

worker(Module) ->
    #{id => Module,
      start => {Module, start_link, []},
      restart => permanent,
      shutdown => 5000,
      type => worker,
      modules => [Module]}.
