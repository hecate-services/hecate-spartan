%%% @doc Handler for the choose_backend command. Validate and emit.
-module(maybe_choose_backend).

-export([handle/1, handle_from_map/1, dispatch/1]).

-dialyzer({nowarn_function, [dispatch/1]}).

-spec handle_from_map(map()) -> {ok, [map()]} | {error, term()}.
handle_from_map(#{did := _, model := _} = M) ->
    case choose_backend_v1:new(M) of
        {ok, Cmd}      -> handle(Cmd);
        {error, _} = E -> E
    end;
handle_from_map(_) ->
    {error, missing_fields}.

-spec handle(choose_backend_v1:choose_backend_v1()) -> {ok, [map()]} | {error, term()}.
handle(Command) ->
    #{model := Mdl} = Map = choose_backend_v1:to_map(Command),
    case byte_size(Mdl) of
        0 -> {error, empty_model};
        _ -> {ok, [backend_chosen_v1:to_map(backend_chosen_v1:new(Map))]}
    end.

-spec dispatch(choose_backend_v1:choose_backend_v1()) ->
    {ok, non_neg_integer(), [map()]} | {error, term()}.
dispatch(Cmd) ->
    #{did := Did} = CmdMap = choose_backend_v1:to_map(Cmd),
    EvoqCmd = evoq_command:new(
        choose_backend,
        soul_aggregate,
        soul_aggregate:stream_id(Did),
        CmdMap,
        #{timestamp => erlang:system_time(millisecond)}
    ),
    Opts = #{store_id => hecate_spartan_store,
             adapter => reckon_evoq_adapter,
             consistency => eventual},
    evoq_command_router:dispatch(EvoqCmd, Opts).
