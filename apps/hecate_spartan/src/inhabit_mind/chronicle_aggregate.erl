%%% @doc Aggregate for one turn in a mind's chronicle.
%%%
%%% One stream per turn (turn-{id}), a single turn_taken_v1 event. Like an agora
%%% post, a turn carries no consistency boundary; the stream exists so that a
%%% turn is an event (provenance, and a substrate the sleep cycle later
%%% condenses). No folding — reuses message_state, the trivial no-fold state.
%%%
%%% One stream per turn, rather than one ever-growing stream per mind, so
%%% appending a turn never loads the mind's whole history. Boot replay reads by
%%% event type (see turn_taken_v1:replay/0), exactly as the agora feed does.
-module(chronicle_aggregate).
-behaviour(evoq_aggregate).

-export([init/1, execute/2, apply/2, state_module/0, stream_id/1]).

-spec state_module() -> module().
state_module() -> message_state.

init(AggregateId) ->
    {ok, message_state:new(AggregateId)}.

%% The turn id is a 32-char hex token minted by the mind.
-spec stream_id(binary()) -> binary().
stream_id(TurnId) when is_binary(TurnId) ->
    <<"turn-", TurnId/binary>>.

execute(_State, #{command_type := <<"record_turn">>} = Payload) ->
    maybe_record_turn:handle_from_map(Payload);
execute(_State, _Payload) ->
    {error, unknown_command}.

apply(State, _Event) ->
    State.
