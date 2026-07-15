%%% @doc Supervises the native minds this node inhabits.
%%%
%%% The roster is config: `application:get_env(hecate_spartan, minds)' is a list
%%% of specs, one per mind. Empty by default, so a node runs no native mind until
%%% it is told to. Each mind is an independent gen_server, restarted on its own.
-module(spartan_mind_sup).
-behaviour(supervisor).

-export([start_link/0, init/1]).

start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

init([]) ->
    Minds = application:get_env(hecate_spartan, minds, []),
    SupFlags = #{strategy => one_for_one, intensity => 5, period => 10},
    {ok, {SupFlags, [child(M) || M <- Minds, is_map(M)]}}.

child(#{name := Name} = Spec) ->
    #{id      => {mind, to_bin(Name)},
      start   => {spartan_mind, start_link, [normalize(Spec)]},
      restart => permanent,
      shutdown => 5000,
      type    => worker,
      modules => [spartan_mind]}.

%% Specs arrive from sys.config as strings; the mind wants binaries.
normalize(Spec) ->
    maps:map(fun(_K, V) -> to_bin(V) end, Spec).

to_bin(V) when is_list(V)   -> unicode:characters_to_binary(V);
to_bin(V) when is_binary(V) -> V;
to_bin(V)                   -> V.
