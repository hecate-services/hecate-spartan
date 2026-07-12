%%% @doc entity_registered_v1 event — an entity is now a member of the commons.
-module(entity_registered_v1).
-behaviour(evoq_event).

-export([new/1, new/4, to_map/1, from_map/1, event_type/0]).

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
