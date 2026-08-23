%%% @doc Supervises the drones of ONE committee.
%%%
%%% Started (unregistered — a node may run several committees at once, each
%%% needing its own instance) and linked by that committee's own process
%%% (committee.erl). Drones are `temporary': a silent or crashed drone just
%%% means one fewer voice this round, nothing here restarts one mid-
%%% deliberation. A plain link does not propagate a NORMAL exit, so this is
%%% explicitly stopped from committee.erl's terminate/2 rather than assumed
%%% to die with it.
-module(committee_drone_sup).
-behaviour(supervisor).

-export([start_link/0, init/1]).
-export([start_drone/2]).

start_link() ->
    supervisor:start_link(?MODULE, []).

init([]) ->
    SupFlags = #{strategy => simple_one_for_one, intensity => 10, period => 10},
    Child = #{id       => committee_drone,
              start    => {committee_drone, start_link, []},
              restart  => temporary,
              shutdown => 5000,
              type     => worker,
              modules  => [committee_drone]},
    {ok, {SupFlags, [Child]}}.

-spec start_drone(pid(), map()) -> {ok, pid()} | {error, term()}.
start_drone(Sup, Spec) ->
    supervisor:start_child(Sup, [Spec]).
