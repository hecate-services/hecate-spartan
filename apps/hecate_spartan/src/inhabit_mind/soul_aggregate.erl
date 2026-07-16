%%% @doc Aggregate for a mind's Soul.
%%%
%%% One stream per mind: soul-{hash(did)}. The stream opens with exactly one
%%% mind_born_v1 (birth is idempotent-guarded — a second bear_mind on an
%%% already-born Soul is rejected), then accretes one event per act of
%%% self-authorship: charter amendments, lessons, reflections, strategy and
%%% working-memory revisions, backend choices.
%%%
%%% Replaying from event 0 reconstructs the whole self, so there is no side
%%% file for identity. The private key is the one thing that cannot live in an
%%% event; it is sealed to disk separately as secret material.
-module(soul_aggregate).
-behaviour(evoq_aggregate).

-include("hecate_spartan_soul.hrl").

-export([init/1, execute/2, apply/2, state_module/0, stream_id/1]).

-spec state_module() -> module().
state_module() -> soul_state.

%% @doc The reckon-db stream id for a mind's Soul. reckon-db requires user
%% stream ids to match `^[a-z]{1,32}-[a-f0-9]{32}$', so the DID (which contains
%% `:') is hashed to a 16-byte, lowercase-hex suffix. Stable per DID, so any
%% slice recomputes the same stream from a DID.
-spec stream_id(binary()) -> binary().
stream_id(Did) when is_binary(Did) ->
    Hash16 = binary:part(macula_crypto_nif:blake3(Did), 0, 16),
    <<"soul-", (binary:encode_hex(Hash16, lowercase))/binary>>.

init(AggregateId) ->
    {ok, soul_state:new(AggregateId)}.

%% @doc Execute command — State FIRST (evoq convention).
execute(State, #{command_type := CmdType} = Payload) ->
    do_execute(CmdType, State, Payload);
execute(_State, _Unknown) ->
    {error, unknown_command}.

%% @doc Apply event — State FIRST. Delegates to the state module.
apply(State, Event) ->
    soul_state:apply_event(State, Event).

%% ===================================================================
%% Command routing
%% ===================================================================

do_execute(<<"bear_mind">>, #soul{status = Status}, Payload) ->
    case Status band ?SOUL_BORN of
        0 -> maybe_bear_mind:handle_from_map(Payload);
        _ -> {error, already_born}
    end;
do_execute(<<"amend_charter">>, _State, Payload) ->
    maybe_amend_charter:handle_from_map(Payload);
do_execute(<<"record_lesson">>, _State, Payload) ->
    maybe_record_lesson:handle_from_map(Payload);
do_execute(<<"record_reflection">>, _State, Payload) ->
    maybe_record_reflection:handle_from_map(Payload);
do_execute(<<"revise_grand_strategy">>, _State, Payload) ->
    maybe_revise_grand_strategy:handle_from_map(Payload);
do_execute(<<"revise_working_memory">>, _State, Payload) ->
    maybe_revise_working_memory:handle_from_map(Payload);
do_execute(<<"choose_backend">>, _State, Payload) ->
    maybe_choose_backend:handle_from_map(Payload);
do_execute(_Unknown, _State, _Payload) ->
    {error, unknown_command}.
