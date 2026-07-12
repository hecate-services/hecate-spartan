%%% @doc Aggregate for a broadcast message.
%%%
%%% One stream per broadcast (`bcast-{id}'), a single message_broadcast_v1
%%% event. Like a routed message it carries no consistency boundary and no
%%% state — it reuses message_state.
-module(broadcast_aggregate).
-behaviour(evoq_aggregate).

-export([init/1, execute/2, apply/2, state_module/0, stream_id/1]).

-spec state_module() -> module().
state_module() -> message_state.

init(AggregateId) ->
    {ok, message_state:new(AggregateId)}.

-spec stream_id(binary()) -> binary().
stream_id(MsgId) when is_binary(MsgId) ->
    <<"bcast-", MsgId/binary>>.

execute(_State, #{command_type := <<"broadcast_message">>} = Payload) ->
    maybe_broadcast_message:handle_from_map(Payload);
execute(_State, _Payload) ->
    {error, unknown_command}.

apply(State, _Event) ->
    State.
