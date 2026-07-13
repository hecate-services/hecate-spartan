%%% @doc entity_registered_v1 event — an entity is now a member of the commons.
-module(entity_registered_v1).
-behaviour(evoq_event).

-export([new/1, new/4, to_map/1, from_map/1, event_type/0]).
-export([replay/0]).

%% One registration per entity, so the whole log fits a single batch for any
%% fleet we can plausibly host on one node.
-define(REPLAY_BATCH, 10000).

-record(entity_registered_v1, {
    entity_name   :: binary(),
    did           :: binary(),
    pubkey        :: binary(),
    registered_at :: integer()
}).

-opaque entity_registered_v1() :: #entity_registered_v1{}.
-export_type([entity_registered_v1/0]).

event_type() -> <<"entity_registered_v1">>.

new(#{entity_name := Name, did := Did, pubkey := PubKey,
      registered_at := At}) ->
    new(Name, Did, PubKey, At).

new(Name, Did, PubKey, At) ->
    #entity_registered_v1{entity_name = Name, did = Did,
                          pubkey = PubKey, registered_at = At}.

-spec to_map(entity_registered_v1()) -> map().
to_map(#entity_registered_v1{entity_name = Name, did = Did,
                            pubkey = PubKey, registered_at = At}) ->
    #{event_type => <<"entity_registered_v1">>,
      entity_name => Name, did => Did, pubkey => PubKey,
      registered_at => At}.

-spec from_map(map()) -> {ok, entity_registered_v1()} | {error, term()}.
from_map(#{entity_name := Name, did := Did, pubkey := PubKey,
           registered_at := At}) ->
    {ok, new(Name, Did, PubKey, At)};
from_map(_) ->
    {error, invalid_entity_registered_event}.

%% @doc Every registration ever recorded, oldest first (the store orders by
%% epoch_us), flattened to plain event maps. `[]' when no store is configured
%% (unit tests) or the store cannot be read.
%%
%% The in-memory read models built from this event call this at boot to rebuild
%% themselves. They must: evoq's store subscription replays the log once, at
%% store start, which `hecate_om:boot/1' does BEFORE the service's supervision
%% tree exists — so no projection is registered yet and the historical events
%% are routed to nobody. Without this, a node restart loses every entity in the
%% registry (the mesh 404s them, running entities are orphaned) even though the
%% events are safe in reckon-db.
-spec replay() -> [map()].
replay() ->
    replay_from(application:get_env(hecate_spartan, event_store_id)).

replay_from(undefined) ->
    [];
replay_from({ok, StoreId}) ->
    case catch evoq_event_store:read_events_by_types(
                 StoreId, [event_type()], ?REPLAY_BATCH) of
        {ok, Events} when is_list(Events) -> Events;
        _Unavailable                      -> []
    end.
