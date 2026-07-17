%%% @doc Supervises the native minds this node inhabits.
%%%
%%% Which minds run here is a per-node choice, so no node ever runs one by
%%% accident. The roster comes from `HECATE_SPARTAN_MINDS' in the env: a
%%% comma-separated list of names (e.g. "armstrong"). Each name becomes one mind,
%%% wearing the shared role from the `mind_role' config with its own name filled
%%% in. If the env var is unset the app-env `minds' list is used instead (full
%%% specs, for tests and programmatic setups); by default that is empty.
-module(spartan_mind_sup).
-behaviour(supervisor).

-export([start_link/0, init/1]).

start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

init([]) ->
    SupFlags = #{strategy => one_for_one, intensity => 5, period => 10},
    {ok, {SupFlags, [child(S) || S <- specs()]}}.

%% --- roster ---

specs() ->
    case names_from_env() of
        []    -> [normalize(M) || M <- application:get_env(hecate_spartan, minds, []),
                                  is_map(M)];
        Names -> [spec(N) || N <- Names]
    end.

names_from_env() ->
    case os:getenv("HECATE_SPARTAN_MINDS") of
        false -> [];
        ""    -> [];
        S     -> [T || N <- string:tokens(S, ","), (T = string:trim(N)) =/= ""]
    end.

spec(Name) ->
    Bin = unicode:characters_to_binary(Name),
    #{name => Bin, character => render_role(Bin)}.

%% A mind's founding brief reaches it as data, not code. HECATE_MIND_ROLE, if
%% set, is used verbatim as the brief (write the mind's purpose there, naming it
%% however you like). Otherwise the app-env `mind_role' template is rendered
%% with the mind's name. Either way the brief becomes the mind's founding brief,
%% written into its Soul at birth; the core stays agnostic.
render_role(Name) ->
    case os:getenv("HECATE_MIND_ROLE") of
        Brief when is_list(Brief), Brief =/= "" ->
            unicode:characters_to_binary(Brief);
        _Unset ->
            render_template(Name)
    end.

render_template(Name) ->
    Tmpl = application:get_env(hecate_spartan, mind_role, "You are ~ts."),
    unicode:characters_to_binary(io_lib:format(Tmpl, [Name])).

%% --- child specs ---

child(#{name := Name} = Spec) ->
    #{id       => {mind, to_bin(Name)},
      start    => {spartan_mind, start_link, [normalize(Spec)]},
      restart  => permanent,
      shutdown => 5000,
      type     => worker,
      modules  => [spartan_mind]}.

normalize(Spec) ->
    maps:map(fun(_K, V) -> to_bin(V) end, Spec).

to_bin(V) when is_list(V)   -> unicode:characters_to_binary(V);
to_bin(V) when is_binary(V) -> V;
to_bin(V)                   -> V.
