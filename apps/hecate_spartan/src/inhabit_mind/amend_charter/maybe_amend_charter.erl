%%% @doc Handler for the amend_charter command. Validate and emit.
-module(maybe_amend_charter).

-export([handle/1, handle_from_map/1, dispatch/1]).

-dialyzer({nowarn_function, [dispatch/1]}).

-spec handle_from_map(map()) -> {ok, [map()]} | {error, term()}.
handle_from_map(#{did := _, entry_type := _, statement := _} = M) ->
    case amend_charter_v1:new(M) of
        {ok, Cmd}      -> handle(Cmd);
        {error, _} = E -> E
    end;
handle_from_map(_) ->
    {error, missing_fields}.

-spec handle(amend_charter_v1:amend_charter_v1()) -> {ok, [map()]} | {error, term()}.
handle(Command) ->
    #{entry_type := T, statement := S} = Map = amend_charter_v1:to_map(Command),
    case validate(T, S) of
        ok ->
            Event = charter_amended_v1:new(Map),
            {ok, [charter_amended_v1:to_map(Event)]};
        {error, Reason} ->
            {error, Reason}
    end.

-spec dispatch(amend_charter_v1:amend_charter_v1()) ->
    {ok, non_neg_integer(), [map()]} | {error, term()}.
dispatch(Cmd) ->
    #{did := Did} = CmdMap = amend_charter_v1:to_map(Cmd),
    EvoqCmd = evoq_command:new(
        amend_charter,
        soul_aggregate,
        soul_aggregate:stream_id(Did),
        CmdMap,
        #{timestamp => erlang:system_time(millisecond)}
    ),
    Opts = #{store_id => hecate_spartan_store,
             adapter => reckon_evoq_adapter,
             consistency => eventual},
    evoq_command_router:dispatch(EvoqCmd, Opts).

validate(EntryType, Statement) ->
    case {byte_size(EntryType), byte_size(Statement)} of
        {0, _} -> {error, entry_type_required};
        {_, 0} -> {error, empty_statement};
        _      -> ok
    end.
