%%% @doc Aggregate for a single Spartan entity.
%%%
%%% One stream per entity: entity-{did}. Manages the entity's membership
%%% lifecycle. Register is idempotent-guarded — a second register on an
%%% already-registered entity is rejected (the entity re-registers to refresh
%%% its UCAN, which does not re-emit the event).
-module(entity_aggregate).
-behaviour(evoq_aggregate).

-include("hecate_spartan_entity.hrl").

-export([init/1, execute/2, apply/2, state_module/0]).

-spec state_module() -> module().
state_module() -> entity_state.

init(AggregateId) ->
    {ok, entity_state:new(AggregateId)}.

%% @doc Execute command — State FIRST (evoq convention).
execute(State, #{command_type := CmdType} = Payload) ->
    do_execute(CmdType, State, Payload);
execute(_State, _Unknown) ->
    {error, unknown_command}.

%% @doc Apply event — State FIRST. Delegates to the state module.
apply(State, Event) ->
    entity_state:apply_event(State, Event).

%% ===================================================================
%% Command routing
%% ===================================================================

do_execute(register_entity, #entity_state{status = Status}, Payload) ->
    case Status band ?ENTITY_REGISTERED of
        0 -> maybe_register_entity:handle_from_map(Payload);
        _ -> {error, already_registered}
    end;
do_execute(_Unknown, _State, _Payload) ->
    {error, unknown_command}.
