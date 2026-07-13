%%% @doc report_activity_v1 command — an entity reports what it is doing.
%%%
%%% Messages show what an agent SAYS. This shows what it is DOING between
%%% messages: the action it just took, the thought it just had, the model call
%%% it just made. Without it, an autonomous agent looks idle for minutes at a
%%% time and a watcher has no idea whether it is thinking or dead.
-module(report_activity_v1).
-behaviour(evoq_command).

-export([new/1, new/5, to_map/1, from_map/1, command_type/0]).

-record(report_activity_v1, {
    activity_id :: binary(),
    did         :: binary(),
    kind        :: binary(),   %% action | thought | speech | model | alert | cycle
    summary     :: binary(),
    at          :: integer()
}).

-opaque report_activity_v1() :: #report_activity_v1{}.
-export_type([report_activity_v1/0]).

command_type() -> report_activity.

new(#{activity_id := I, did := D, kind := K, summary := S} = M) ->
    {ok, new(I, D, K, S, maps:get(at, M, erlang:system_time(millisecond)))};
new(_) ->
    {error, missing_fields}.

new(Id, Did, Kind, Summary, At) ->
    #report_activity_v1{activity_id = Id, did = Did, kind = Kind,
                        summary = Summary, at = At}.

-spec to_map(report_activity_v1()) -> map().
to_map(#report_activity_v1{activity_id = I, did = D, kind = K,
                           summary = S, at = At}) ->
    #{command_type => <<"report_activity">>,
      activity_id => I, did => D, kind => K, summary => S, at => At}.

-spec from_map(map()) -> {ok, report_activity_v1()} | {error, term()}.
from_map(#{activity_id := I, did := D, kind := K, summary := S} = M) ->
    {ok, new(I, D, K, S, maps:get(at, M, erlang:system_time(millisecond)))};
from_map(_) ->
    {error, invalid_report_activity_command}.
