%%% @doc Handler for the report_activity command.
-module(maybe_report_activity).

-export([handle/1, handle_from_map/1, dispatch/1]).

-dialyzer({nowarn_function, [dispatch/1]}).

%% Kinds a watcher can colour differently. Anything else is rejected rather than
%% rendered as a mystery badge.
-define(KINDS, [<<"action">>, <<"thought">>, <<"speech">>, <<"model">>,
                <<"alert">>, <<"cycle">>]).

-spec handle_from_map(map()) -> {ok, [map()]} | {error, term()}.
handle_from_map(#{activity_id := I, did := D, kind := K, summary := S} = P) ->
    At = maps:get(at, P, erlang:system_time(millisecond)),
    handle(report_activity_v1:new(I, D, K, S, At));
handle_from_map(_) ->
    {error, missing_fields}.

-spec handle(report_activity_v1:report_activity_v1()) ->
    {ok, [map()]} | {error, term()}.
handle(Command) ->
    #{did := D, kind := K, summary := S} = Map = report_activity_v1:to_map(Command),
    case validate(D, K, S) of
        ok              -> {ok, [activity_reported_v1:to_map(
                                   activity_reported_v1:new(Map))]};
        {error, Reason} -> {error, Reason}
    end.

-spec dispatch(report_activity_v1:report_activity_v1()) ->
    {ok, non_neg_integer(), [map()]} | {error, term()}.
dispatch(Cmd) ->
    #{activity_id := Id} = CmdMap = report_activity_v1:to_map(Cmd),
    EvoqCmd = evoq_command:new(
        report_activity,
        activity_aggregate,
        activity_aggregate:stream_id(Id),
        CmdMap,
        #{timestamp => erlang:system_time(millisecond)}
    ),
    Opts = #{store_id => hecate_spartan_store,
             adapter => reckon_evoq_adapter,
             consistency => eventual},
    evoq_command_router:dispatch(EvoqCmd, Opts).

validate(Did, Kind, Summary) ->
    case {byte_size(Did), lists:member(Kind, ?KINDS), byte_size(Summary)} of
        {0, _, _}     -> {error, did_required};
        {_, false, _} -> {error, unknown_kind};
        {_, _, 0}     -> {error, empty_summary};
        _             -> ok
    end.
