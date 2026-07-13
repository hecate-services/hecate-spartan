%%% @doc Projection: entity_registered_v1 -> entities registry ETS.
-module(entity_registered_v1_to_entities).
-behaviour(evoq_projection).

-export([interested_in/0, init/1, project/4]).
-export([row/1]).

-define(TABLE, entities).

interested_in() ->
    [<<"entity_registered_v1">>].

init(_Config) ->
    {ok, RM} = evoq_read_model:new(evoq_read_model_ets, #{name => ?TABLE}),
    {ok, #{}, RM}.

project(#{data := Data} = Event, _Metadata, State, RM) ->
    case get_event_type(Event) of
        <<"entity_registered_v1">> -> project_registered(Data, State, RM);
        _                          -> {ok, State, RM}
    end;
project(_Event, _Metadata, State, RM) ->
    {ok, State, RM}.

%% --- entity_registered: upsert the directory row ---
project_registered(Data, State, RM) ->
    {Did, Entry} = row(Data),
    {ok, RM2} = evoq_read_model:put(Did, Entry, RM),
    {ok, State, RM2}.

%% @doc The registry row an entity_registered_v1 becomes. Exported so the table
%% owner rebuilds identical rows when it replays the log at boot.
-spec row(map()) -> {binary(), map()}.
row(Data) ->
    Did = gf(did, Data),
    At = gf(registered_at, Data),
    {Did, #{
        did           => Did,
        entity_name   => gf(entity_name, Data),
        pubkey        => gf(pubkey, Data),
        status        => 1,
        registered_at => At,
        last_seen     => At
    }}.

%% --- Internal ---

get_event_type(#{event_type := T}) -> T;
get_event_type(_)                  -> undefined.

%% Event fields may come back keyed by atom or binary depending on the
%% serialization round-trip; accept either.
gf(AtomKey, Data) ->
    maps:get(AtomKey, Data, maps:get(atom_to_binary(AtomKey, utf8), Data, undefined)).
