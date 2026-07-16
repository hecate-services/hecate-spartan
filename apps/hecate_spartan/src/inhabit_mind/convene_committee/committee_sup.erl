%%% @doc Supervises the committees convened on this node.
%%%
%%% Committees are dynamic and short-lived: a mind convenes one when a matter
%%% deserves several voices, it deliberates for a bounded number of rounds, then
%%% it stops. So the children are `temporary' (a finished committee stays
%%% finished; nothing restarts it) under a simple_one_for_one supervisor that
%%% exists only to birth and count them. This is the convene_committee slice's
%%% own supervision, not a central registry of anything.
-module(committee_sup).
-behaviour(supervisor).

-export([start_link/0, init/1]).
-export([start_committee/1, count/0]).

start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

init([]) ->
    SupFlags = #{strategy => simple_one_for_one, intensity => 10, period => 10},
    Child = #{id       => committee,
              start    => {committee, start_link, []},
              restart  => temporary,
              shutdown => 5000,
              type     => worker,
              modules  => [committee]},
    {ok, {SupFlags, [Child]}}.

-spec start_committee(map()) -> {ok, pid()} | {error, term()}.
start_committee(Spec) ->
    supervisor:start_child(?MODULE, [Spec]).

%% @doc How many committees are deliberating right now.
-spec count() -> non_neg_integer().
count() ->
    proplists:get_value(active, supervisor:count_children(?MODULE), 0).
