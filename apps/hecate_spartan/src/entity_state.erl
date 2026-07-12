%%% @doc State module for the entity aggregate. Owns the record and event
%%% folding.
-module(entity_state).
-behaviour(evoq_state).

-include("hecate_spartan_entity.hrl").

-export([new/1, apply_event/2, to_map/1]).

-type state() :: #entity_state{}.
-export_type([state/0]).

-spec new(binary()) -> state().
new(_AggregateId) ->
    #entity_state{status = 0}.

-spec apply_event(state(), map()) -> state().
apply_event(State, #{event_type := EventType} = Event) ->
    do_apply(EventType, State, Event);
apply_event(State, _) ->
    State.

-spec to_map(state()) -> map().
to_map(#entity_state{} = S) ->
    #{did           => S#entity_state.did,
      entity_name   => S#entity_state.entity_name,
      pubkey        => S#entity_state.pubkey,
      status        => S#entity_state.status,
      registered_at => S#entity_state.registered_at}.

%% ===================================================================
%% Event application
%% ===================================================================

do_apply(<<"entity_registered_v1">>, State, Event) ->
    State#entity_state{
        did           = gf(<<"did">>, did, Event),
        entity_name   = gf(<<"entity_name">>, entity_name, Event),
        pubkey        = gf(<<"pubkey">>, pubkey, Event),
        registered_at = gf(<<"registered_at">>, registered_at, Event),
        status        = State#entity_state.status bor ?ENTITY_REGISTERED
    };
do_apply(_Unknown, State, _Event) ->
    State.

gf(BinKey, AtomKey, Event) ->
    maps:get(BinKey, Event, maps:get(AtomKey, Event, undefined)).
