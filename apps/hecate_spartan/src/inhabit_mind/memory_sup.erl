%%% @doc The memory faculty, as a supervision sub-tree.
%%%
%%% One supervisor per mind; a `memory_store' child per tier (STM, CMO, MSO) plus
%%% the `sleep_cycle' consolidation process. A crash in one tier restarts it
%%% alone, reloading its file. This is the "memory faculty" of
%%% docs/DESIGN_MIND_FACULTIES.md: not one area, but a small society of processes
%%% (the tiered stores) with a process that tends them (the Sleep Cycle).
%%%
%%% Started by `memory:open/2', linked to the mind. Long-term semantic recall
%%% (mind_memory / hecate-vector) remains the mind's separate LTM tier for now;
%%% folding it in here is a later iteration.
-module(memory_sup).
-behaviour(supervisor).

-export([start_link/2, init/1]).

-spec start_link(binary(), binary()) -> {ok, pid()} | {error, term()}.
start_link(Did, Dir) ->
    supervisor:start_link(?MODULE, {Did, Dir}).

init({Did, Dir}) ->
    Stores = [store_child(Did, Dir, Tier, File) || {Tier, File} <- memory:tiers()],
    Children = Stores ++ [sleep_child(Did)],
    {ok, {#{strategy => one_for_one, intensity => 10, period => 60}, Children}}.

store_child(Did, Dir, Tier, File) ->
    #{id      => Tier,
      start   => {memory_store, start_link,
                  [#{did => Did, tier => Tier,
                     path => iolist_to_binary(filename:join(Dir, File))}]},
      restart => permanent,
      type    => worker}.

sleep_child(Did) ->
    #{id      => sleep_cycle,
      start   => {sleep_cycle, start_link, [#{did => Did}]},
      restart => permanent,
      type    => worker}.
