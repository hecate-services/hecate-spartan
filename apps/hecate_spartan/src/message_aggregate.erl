%%% @doc Aggregate for a routed message.
%%%
%%% One stream per message (`msg-{id}'), a single message_routed_v1 event.
%%% Messages carry no consistency boundary — the stream exists only to leave a
%%% local, ordered record of the routing. No folding.
-module(message_aggregate).
-behaviour(evoq_aggregate).

-export([init/1, execute/2, apply/2, state_module/0, stream_id/1]).

-spec state_module() -> module().
state_module() -> message_state.

init(AggregateId) ->
    {ok, message_state:new(AggregateId)}.

%% The message id is already a 32-char hex token (see route_message_api).
-spec stream_id(binary()) -> binary().
stream_id(MsgId) when is_binary(MsgId) ->
    <<"msg-", MsgId/binary>>.

execute(_State, #{command_type := <<"route_message">>} = Payload) ->
    maybe_route_message:handle_from_map(Payload);
execute(_State, _Payload) ->
    {error, unknown_command}.

apply(State, _Event) ->
    State.
