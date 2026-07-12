%%% @doc register_entity_v1 command — a self-sovereign entity joins the commons.
-module(register_entity_v1).
-behaviour(evoq_command).

-export([new/1, new/4, to_map/1, from_map/1, command_type/0]).

-record(register_entity_v1, {
    entity_name   :: binary(),
    did           :: binary(),
    pubkey        :: binary(),
    registered_at :: integer()
}).

-opaque register_entity_v1() :: #register_entity_v1{}.
-export_type([register_entity_v1/0]).

command_type() -> register_entity.

new(#{entity_name := Name, did := Did, pubkey := PubKey,
      registered_at := At}) ->
    {ok, new(Name, Did, PubKey, At)};
new(_) ->
    {error, missing_fields}.

new(Name, Did, PubKey, At) ->
    #register_entity_v1{entity_name = Name, did = Did,
                        pubkey = PubKey, registered_at = At}.

-spec to_map(register_entity_v1()) -> map().
to_map(#register_entity_v1{entity_name = Name, did = Did,
                          pubkey = PubKey, registered_at = At}) ->
    %% command_type (binary) must ride in the payload — the aggregate matches
    %% on it; evoq passes the payload to execute/2 unchanged.
    #{command_type => <<"register_entity">>,
      entity_name => Name, did => Did, pubkey => PubKey, registered_at => At}.

-spec from_map(map()) -> {ok, register_entity_v1()} | {error, term()}.
from_map(#{entity_name := Name, did := Did, pubkey := PubKey,
           registered_at := At}) ->
    {ok, new(Name, Did, PubKey, At)};
from_map(_) ->
    {error, invalid_register_entity_command}.
