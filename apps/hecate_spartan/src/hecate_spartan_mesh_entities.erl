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

%% @doc Upsert a directory row.
%% Entry: #{did, entity_name, home, last_seen, registered_at}.
-spec upsert(map()) -> ok.
upsert(#{did := Did} = Entry) when is_binary(Did) ->
    claim(maps:get(entity_name, Entry, undefined), Did,
          maps:get(registered_at, Entry, 0), Entry).

%% A name resolves to exactly ONE live DID: the newest registration holds it,
%% older claims are dropped from the directory. Entities are self-sovereign, so
%% a restart with a lost keypair comes back as a new DID under the same name —
%% without this, both DIDs sit in the directory and a peer resolving the name
%% has even odds of routing to the dead one. The event log keeps every claim;
%% the directory answers "who is reachable as this name NOW".
claim(undefined, Did, _At, Entry) ->
    insert(Did, Entry);
claim(Name, Did, At, Entry) ->
    supersede(rivals(Name, Did), At, Did, Entry).

supersede(Rivals, At, Did, Entry) ->
    Newer = lists:any(fun({_D, RivalAt}) -> RivalAt > At end, Rivals),
    do_supersede(Newer, Rivals, Did, Entry).

%% A newer claim on this name already stands; leave it.
do_supersede(true, _Rivals, _Did, _Entry) ->
    ok;
do_supersede(false, Rivals, Did, Entry) ->
    lists:foreach(fun({D, _}) -> ets:delete(?TABLE, D) end, Rivals),
    insert(Did, Entry).

rivals(Name, Did) ->
    [{D, maps:get(registered_at, E, 0)}
     || {D, E} <- ets:tab2list(?TABLE),
        D =/= Did, maps:get(entity_name, E, undefined) =:= Name].

insert(Did, Entry) ->
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
    Rebuilt = rebuild_local(),
    logger:info("[spartan] mesh directory seeded with ~b locally-homed entities",
                [Rebuilt]),
    {ok, #{}}.

handle_call(_Req, _From, S) -> {reply, {error, unknown_call}, S}.
handle_cast(_Msg, S)       -> {noreply, S}.
handle_info(_Info, S)      -> {noreply, S}.
terminate(_Reason, _S)     -> ok.

%% --- Internal ---

%% Seed the directory with this instance's own entities, replayed from the log.
%% The announce PM only fires on live registrations, so after a restart the node
%% would otherwise not even know about the entities it is homing — and would 404
%% them. Peers' rows come back on their re-announce (federation_registry).
rebuild_local() ->
    rebuild_local(safe_service_did()).

rebuild_local(undefined) ->
    0;
rebuild_local(Home) ->
    Events = entity_registered_v1:replay(),
    lists:foreach(fun(E) -> upsert_local(E, Home) end, Events),
    length(Events).

upsert_local(Event, Home) ->
    {Did, Entry} = entity_registered_v1_to_entities:row(Event),
    upsert(#{did => Did,
             entity_name => maps:get(entity_name, Entry),
             home => Home,
             locale => hecate_spartan_service:locale(),
             registered_at => maps:get(registered_at, Entry, 0),
             last_seen => erlang:system_time(millisecond)}).

safe_service_did() ->
    try hecate_spartan_identity:service_did()
    catch _:_ -> undefined
    end.
