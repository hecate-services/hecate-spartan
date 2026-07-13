%%% @doc Process manager: on entity_registered_v1, announce the entity to the
%%% federation.
%%%
%%% Two effects: (1) upsert the local `mesh_entities' row (home = this instance),
%%% since a node's own mesh publishes may not loop back to itself; (2) publish an
%%% `entity_announced' FACT on `spartan/registry' so peer instances learn this
%%% entity exists and where it is homed. Degrades safely while dark.
-module(on_entity_registered_announce).
-behaviour(evoq_projection).

-export([interested_in/0, init/1, project/4, fact/2, topic/0]).

-define(TABLE, entity_announce_checkpoint).

interested_in() ->
    [<<"entity_registered_v1">>].

init(_Config) ->
    {ok, RM} = evoq_read_model:new(evoq_read_model_ets, #{name => ?TABLE}),
    {ok, #{}, RM}.

project(#{data := Data} = Event, _Metadata, State, RM) ->
    case get_event_type(Event) of
        <<"entity_registered_v1">> ->
            Home = hecate_spartan_identity:service_did(),
            Did = gf(did, Data),
            hecate_spartan_mesh_entities:upsert(
                #{did => Did, entity_name => gf(entity_name, Data),
                  home => Home, locale => hecate_spartan_service:locale(),
                  registered_at => gf(registered_at, Data),
                  last_seen => erlang:system_time(millisecond)}),
            _ = publish_fact(Data, Home),
            {ok, RM2} = evoq_read_model:put(Did, announced, RM),
            {ok, State, RM2};
        _ ->
            {ok, State, RM}
    end;
project(_Event, _Metadata, State, RM) ->
    {ok, State, RM}.

-spec topic() -> binary().
topic() -> <<"spartan/registry">>.

%% `registered_at' travels with the announcement: it is how a peer decides which
%% DID currently holds a name when an entity has re-registered under a new key.
-spec fact(map(), binary()) -> map().
fact(Data, Home) ->
    #{type        => entity_announced,
      did         => gf(did, Data),
      entity_name => gf(entity_name, Data),
      home        => Home,
      locale      => hecate_spartan_service:locale(),
      registered_at => gf(registered_at, Data),
      announced_at => erlang:system_time(millisecond)}.

%% --- Internal ---

publish_fact(Data, Home) ->
    case {hecate_om:macula_client(), hecate_om_identity:realm()} of
        {{ok, Pool}, {ok, Realm}} ->
            catch macula:publish(Pool, Realm, topic(), fact(Data, Home)),
            ok;
        _DarkOrNoRealm ->
            ok
    end.

get_event_type(#{event_type := T}) -> T;
get_event_type(_)                  -> undefined.

gf(AtomKey, Data) ->
    maps:get(AtomKey, Data, maps:get(atom_to_binary(AtomKey, utf8), Data, undefined)).
