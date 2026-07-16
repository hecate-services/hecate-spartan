%%% @doc Handler for the revise_grand_strategy command. Validate and emit.
-module(maybe_revise_grand_strategy).

-export([handle/1, handle_from_map/1, dispatch/1]).

-dialyzer({nowarn_function, [dispatch/1]}).

-spec handle_from_map(map()) -> {ok, [map()]} | {error, term()}.
handle_from_map(#{did := _, text := _} = M) ->
    case revise_grand_strategy_v1:new(M) of
        {ok, Cmd}      -> handle(Cmd);
        {error, _} = E -> E
    end;
handle_from_map(_) ->
    {error, missing_fields}.

-spec handle(revise_grand_strategy_v1:revise_grand_strategy_v1()) ->
    {ok, [map()]} | {error, term()}.
handle(Command) ->
    Map = revise_grand_strategy_v1:to_map(Command),
    {ok, [grand_strategy_revised_v1:to_map(grand_strategy_revised_v1:new(Map))]}.

-spec dispatch(revise_grand_strategy_v1:revise_grand_strategy_v1()) ->
    {ok, non_neg_integer(), [map()]} | {error, term()}.
dispatch(Cmd) ->
    #{did := Did} = CmdMap = revise_grand_strategy_v1:to_map(Cmd),
    EvoqCmd = evoq_command:new(
        revise_grand_strategy,
        soul_aggregate,
        soul_aggregate:stream_id(Did),
        CmdMap,
        #{timestamp => erlang:system_time(millisecond)}
    ),
    Opts = #{store_id => hecate_spartan_store,
             adapter => reckon_evoq_adapter,
             consistency => eventual},
    evoq_command_router:dispatch(EvoqCmd, Opts).
