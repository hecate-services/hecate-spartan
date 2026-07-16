%%% @doc Handler for the record_lesson command. Validate and emit.
-module(maybe_record_lesson).

-export([handle/1, handle_from_map/1, dispatch/1]).

-dialyzer({nowarn_function, [dispatch/1]}).

-spec handle_from_map(map()) -> {ok, [map()]} | {error, term()}.
handle_from_map(#{did := _, lesson := _} = M) ->
    case record_lesson_v1:new(M) of
        {ok, Cmd}      -> handle(Cmd);
        {error, _} = E -> E
    end;
handle_from_map(_) ->
    {error, missing_fields}.

-spec handle(record_lesson_v1:record_lesson_v1()) -> {ok, [map()]} | {error, term()}.
handle(Command) ->
    #{lesson := L} = Map = record_lesson_v1:to_map(Command),
    case byte_size(L) of
        0 -> {error, empty_lesson};
        _ -> {ok, [lesson_recorded_v1:to_map(lesson_recorded_v1:new(Map))]}
    end.

-spec dispatch(record_lesson_v1:record_lesson_v1()) ->
    {ok, non_neg_integer(), [map()]} | {error, term()}.
dispatch(Cmd) ->
    #{did := Did} = CmdMap = record_lesson_v1:to_map(Cmd),
    EvoqCmd = evoq_command:new(
        record_lesson,
        soul_aggregate,
        soul_aggregate:stream_id(Did),
        CmdMap,
        #{timestamp => erlang:system_time(millisecond)}
    ),
    Opts = #{store_id => hecate_spartan_store,
             adapter => reckon_evoq_adapter,
             consistency => eventual},
    evoq_command_router:dispatch(EvoqCmd, Opts).
