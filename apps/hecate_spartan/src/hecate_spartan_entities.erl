%%% @doc Entity registry read model — the discovery/directory table.
%%%
%%% Owns the public named ETS table `entities'. Starting this gen_server
%%% before the projection guarantees the table outlives any projection
%%% restart (ETS tables die with their owner). The projection writes here;
%%% queries read here directly.
%%%
%%% The table is in-memory, so it is rebuilt from the event log at boot (see
%%% `entity_registered_v1:replay/1'). Live events arrive via the projection;
%%% history arrives here. Without the rebuild a node restart drops every
%%% registration on the floor while the events sit safely in reckon-db.
-module(hecate_spartan_entities).
-behaviour(gen_server).

-export([start_link/0, upsert/2, get/1, all/0, count/0]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2]).

-define(TABLE, entities).

-spec start_link() -> {ok, pid()} | {error, term()}.
start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

%% @doc Upsert a directory row (the register_entity handler writes through here).
-spec upsert(binary(), map()) -> ok.
upsert(Did, Entry) when is_binary(Did) ->
    true = ets:insert(?TABLE, {Did, Entry}),
    ok.

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
    Rebuilt = rebuild(),
    logger:info("[spartan] entity registry rebuilt from the log: ~b entities",
                [Rebuilt]),
    {ok, #{}}.

handle_call(_Req, _From, S) -> {reply, {error, unknown_call}, S}.
handle_cast(_Msg, S)       -> {noreply, S}.
handle_info(_Info, S)      -> {noreply, S}.
terminate(_Reason, _S)     -> ok.

%% --- Internal ---

%% Replay every registration into the table. Idempotent (upsert by DID) and
%% ordered oldest-first, so the latest registration for a DID wins.
rebuild() ->
    Events = entity_registered_v1:replay(),
    lists:foreach(fun insert_row/1, Events),
    length(Events).

insert_row(Event) ->
    {Did, Entry} = maybe_register_entity:row(Event),
    true = ets:insert(?TABLE, {Did, Entry}),
    ok.
