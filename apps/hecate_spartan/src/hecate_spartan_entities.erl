%%% @doc Entity registry read model — the discovery/directory table.
%%%
%%% Owns the public named ETS table `entities'. Starting this gen_server
%%% before the projection guarantees the table outlives any projection
%%% restart (ETS tables die with their owner). The projection writes here;
%%% queries read here directly.
-module(hecate_spartan_entities).
-behaviour(gen_server).

-export([start_link/0, get/1, all/0, count/0]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2]).

-define(TABLE, entities).

-spec start_link() -> {ok, pid()} | {error, term()}.
start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

%% @doc Look up one entity by its DID.
-spec get(binary()) -> {ok, map()} | {error, not_found}.
get(Did) ->
    case ets:lookup(?TABLE, Did) of
        [{_, Entry}] -> {ok, Entry};
        []           -> {error, not_found}
    end.

%% @doc All registered entities (discovery).
-spec all() -> [map()].
all() ->
    [Entry || {_Did, Entry} <- ets:tab2list(?TABLE)].

-spec count() -> non_neg_integer().
count() ->
    ets:info(?TABLE, size).

init([]) ->
    ?TABLE = ets:new(?TABLE, [set, public, named_table, {read_concurrency, true}]),
    {ok, #{}}.

handle_call(_Req, _From, S) -> {reply, {error, unknown_call}, S}.
handle_cast(_Msg, S)       -> {noreply, S}.
handle_info(_Info, S)      -> {noreply, S}.
terminate(_Reason, _S)     -> ok.
