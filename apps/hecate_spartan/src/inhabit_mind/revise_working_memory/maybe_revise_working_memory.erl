%%% @doc Handler for the revise_working_memory command. Validate and emit.
-module(maybe_revise_working_memory).

-export([handle/1, handle_from_map/1, dispatch/1]).

-dialyzer({nowarn_function, [dispatch/1]}).

-spec handle_from_map(map()) -> {ok, [map()]} | {error, term()}.
handle_from_map(#{did := _, text := _} = M) ->
    case revise_working_memory_v1:new(M) of
        {ok, Cmd}      -> handle(Cmd);
        {error, _} = E -> E
    end;
handle_from_map(_) ->
    {error, missing_fields}.

-spec handle(revise_working_memory_v1:revise_working_memory_v1()) ->
    {ok, [map()]} | {error, term()}.
handle(Command) ->
    Map = revise_working_memory_v1:to_map(Command),
    {ok, [working_memory_revised_v1:to_map(working_memory_revised_v1:new(Map))]}.

-spec dispatch(revise_working_memory_v1:revise_working_memory_v1()) ->
    {ok, non_neg_integer(), [map()]} | {error, term()}.
dispatch(Cmd) ->
    #{did := Did} = CmdMap = revise_working_memory_v1:to_map(Cmd),
    EvoqCmd = evoq_command:new(
        revise_working_memory,
        soul_aggregate,
        soul_aggregate:stream_id(Did),
        CmdMap,
        #{timestamp => erlang:system_time(millisecond)}
    ),
    Opts = #{store_id => hecate_spartan_store,
             adapter => reckon_evoq_adapter,
             consistency => eventual},
    evoq_command_router:dispatch(EvoqCmd, Opts).
