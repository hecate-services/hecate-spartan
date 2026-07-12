%%% @doc Mesh-wide entity registry read model.
%%%
%%% Unlike `hecate_spartan_entities' (this instance's LOCALLY-homed entities),
%%% this holds every entity announced across the federation: local ones (written
%%% by the announce PM) and remote ones (written by `federation_registry' from
%%% mesh announcements). Each row carries `home' = the service DID of the
%%% instance that entity is homed on, so routing can decide local vs remote.
-module(hecate_spartan_mesh_entities).
-behaviour(gen_server).

-export([start_link/0, upsert/1, get/1, all/0, count/0]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2]).

-define(TABLE, mesh_entities).

-spec start_link() -> {ok, pid()} | {error, term()}.
start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

%% @doc Upsert a directory row. Entry: #{did, entity_name, home, last_seen}.
-spec upsert(map()) -> ok.
upsert(#{did := Did} = Entry) when is_binary(Did) ->
    true = ets:insert(?TABLE, {Did, Entry}),
    ok.

-spec get(binary()) -> {ok, map()} | {error, not_found}.
get(Did) ->
    case ets:lookup(?TABLE, Did) of
        [{_, Entry}] -> {ok, Entry};
        []           -> {error, not_found}
    end.

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
