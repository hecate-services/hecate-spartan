%%% @doc Handler for the broadcast_message command.
-module(maybe_broadcast_message).

-export([handle/1, handle_from_map/1, dispatch/1]).

-dialyzer({nowarn_function, [dispatch/1]}).

-spec handle_from_map(map()) -> {ok, [map()]} | {error, term()}.
handle_from_map(#{msg_id := M, from := F, body := B} = Payload) ->
    At = maps:get(sent_at, Payload, erlang:system_time(millisecond)),
    handle(broadcast_message_v1:new(M, F, B, At));
handle_from_map(_) ->
    {error, missing_fields}.

-spec handle(broadcast_message_v1:broadcast_message_v1()) ->
    {ok, [map()]} | {error, term()}.
handle(Command) ->
    #{from := F, body := B} = Map = broadcast_message_v1:to_map(Command),
    case validate(F, B) of
        ok ->
            Event = message_broadcast_v1:new(Map),
            {ok, [message_broadcast_v1:to_map(Event)]};
        {error, Reason} ->
            {error, Reason}
    end.

-spec dispatch(broadcast_message_v1:broadcast_message_v1()) ->
    {ok, non_neg_integer(), [map()]} | {error, term()}.
dispatch(Cmd) ->
    #{msg_id := MsgId} = CmdMap = broadcast_message_v1:to_map(Cmd),
    EvoqCmd = evoq_command:new(
        broadcast_message,
        broadcast_aggregate,
        broadcast_aggregate:stream_id(MsgId),
        CmdMap,
        #{timestamp => erlang:system_time(millisecond)}
    ),
    Opts = #{store_id => hecate_spartan_store,
             adapter => reckon_evoq_adapter,
             consistency => eventual},
    evoq_command_router:dispatch(EvoqCmd, Opts).

validate(From, Body) ->
    case {byte_size(From), byte_size(Body)} of
        {0, _} -> {error, from_required};
        {_, 0} -> {error, empty_body};
        _      -> ok
    end.
