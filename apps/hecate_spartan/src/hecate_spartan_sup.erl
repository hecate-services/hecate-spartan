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
    Children = [],
    {ok, {SupFlags, Children}}.
