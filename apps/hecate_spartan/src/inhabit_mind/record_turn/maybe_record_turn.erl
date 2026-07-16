%%% @doc Handler for the record_turn command. Validate and emit.
-module(maybe_record_turn).

-export([handle/1, handle_from_map/1, dispatch/1]).

-dialyzer({nowarn_function, [dispatch/1]}).

-spec handle_from_map(map()) -> {ok, [map()]} | {error, term()}.
handle_from_map(#{turn_id := _, did := _} = M) ->
    case record_turn_v1:new(M) of
        {ok, Cmd}      -> handle(Cmd);
        {error, _} = E -> E
    end;
handle_from_map(_) ->
    {error, missing_fields}.

-spec handle(record_turn_v1:record_turn_v1()) -> {ok, [map()]} | {error, term()}.
handle(Command) ->
    Map = record_turn_v1:to_map(Command),
    {ok, [turn_taken_v1:to_map(turn_taken_v1:new(Map))]}.

-spec dispatch(record_turn_v1:record_turn_v1()) ->
    {ok, non_neg_integer(), [map()]} | {error, term()}.
dispatch(Cmd) ->
    #{turn_id := Tid} = CmdMap = record_turn_v1:to_map(Cmd),
    EvoqCmd = evoq_command:new(
        record_turn,
        chronicle_aggregate,
        chronicle_aggregate:stream_id(Tid),
        CmdMap,
        #{timestamp => erlang:system_time(millisecond)}
    ),
    Opts = #{store_id => hecate_spartan_store,
             adapter => reckon_evoq_adapter,
             consistency => eventual},
    evoq_command_router:dispatch(EvoqCmd, Opts).
