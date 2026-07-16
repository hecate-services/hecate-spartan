%%% @doc Handler for the bear_mind command.
%%%
%%% Pure domain logic: validate and emit mind_born_v1. The keypair generation
%%% and the sealing of the private key to disk happen in the mind's boot (it
%%% owns its secret material), not here; this handler records only the public
%%% birth into the log.
-module(maybe_bear_mind).

-export([handle/1, handle_from_map/1, dispatch/1]).

-dialyzer({nowarn_function, [dispatch/1]}).

-spec handle_from_map(map()) -> {ok, [map()]} | {error, term()}.
handle_from_map(#{did := _, name := _, founding_brief := _, pubkey := _} = M) ->
    case bear_mind_v1:new(M) of
        {ok, Cmd}      -> handle(Cmd);
        {error, _} = E -> E
    end;
handle_from_map(_) ->
    {error, missing_fields}.

-spec handle(bear_mind_v1:bear_mind_v1()) -> {ok, [map()]} | {error, term()}.
handle(Command) ->
    #{did := Did, name := Name} = Map = bear_mind_v1:to_map(Command),
    case validate(Did, Name) of
        ok ->
            Event = mind_born_v1:new(Map),
            {ok, [mind_born_v1:to_map(Event)]};
        {error, Reason} ->
            {error, Reason}
    end.

-spec dispatch(bear_mind_v1:bear_mind_v1()) ->
    {ok, non_neg_integer(), [map()]} | {error, term()}.
dispatch(Cmd) ->
    #{did := Did} = CmdMap = bear_mind_v1:to_map(Cmd),
    EvoqCmd = evoq_command:new(
        bear_mind,
        soul_aggregate,
        soul_aggregate:stream_id(Did),
        CmdMap,
        #{timestamp => erlang:system_time(millisecond)}
    ),
    Opts = #{store_id => hecate_spartan_store,
             adapter => reckon_evoq_adapter,
             consistency => eventual},
    evoq_command_router:dispatch(EvoqCmd, Opts).

validate(Did, Name) ->
    case {byte_size(Did), byte_size(Name)} of
        {0, _} -> {error, did_required};
        {_, 0} -> {error, name_required};
        _      -> ok
    end.
