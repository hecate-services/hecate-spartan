%%% @doc Aggregate for a single Spartan entity.
%%%
%%% One stream per entity: entity-{did}. Manages the entity's membership
%%% lifecycle. Register is idempotent-guarded — a second register on an
%%% already-registered entity is rejected (the entity re-registers to refresh
%%% its UCAN, which does not re-emit the event).
-module(entity_aggregate).
-behaviour(evoq_aggregate).

-include("hecate_spartan_entity.hrl").

-export([init/1, execute/2, apply/2, state_module/0, stream_id/1]).

-spec state_module() -> module().
state_module() -> entity_state.

%% @doc The reckon-db stream id for an entity. reckon-db requires user stream
%% ids to match `^[a-z]{1,32}-[a-f0-9]{32}$', so the DID (which contains `:')
%% cannot be used raw — we hash it to a 16-byte, lowercase-hex suffix. Stable
%% per DID, so any slice can recompute the same stream from a DID.
-spec stream_id(binary()) -> binary().
stream_id(Did) when is_binary(Did) ->
    Hash16 = binary:part(macula_crypto_nif:blake3(Did), 0, 16),
    <<"entity-", (binary:encode_hex(Hash16, lowercase))/binary>>.

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

%% The router injects command_type into the payload as a binary.
do_execute(<<"register_entity">>, #entity_state{status = Status}, Payload) ->
    case Status band ?ENTITY_REGISTERED of
        0 -> maybe_register_entity:handle_from_map(Payload);
        _ -> {error, already_registered}
    end;
do_execute(_Unknown, _State, _Payload) ->
    {error, unknown_command}.
