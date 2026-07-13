%%% @doc activity_reported_v1 event — an entity did something.
-module(activity_reported_v1).
-behaviour(evoq_event).

-export([new/1, new/5, to_map/1, from_map/1, event_type/0]).

-record(activity_reported_v1, {
    activity_id :: binary(),
    did         :: binary(),
    kind        :: binary(),
    summary     :: binary(),
    at          :: integer()
}).

-opaque activity_reported_v1() :: #activity_reported_v1{}.
-export_type([activity_reported_v1/0]).

event_type() -> <<"activity_reported_v1">>.

new(#{activity_id := I, did := D, kind := K, summary := S} = M) ->
    new(I, D, K, S, maps:get(at, M, erlang:system_time(millisecond))).

new(Id, Did, Kind, Summary, At) ->
    #activity_reported_v1{activity_id = Id, did = Did, kind = Kind,
                          summary = Summary, at = At}.

-spec to_map(activity_reported_v1()) -> map().
to_map(#activity_reported_v1{activity_id = I, did = D, kind = K,
                             summary = S, at = At}) ->
    #{event_type => <<"activity_reported_v1">>,
      activity_id => I, did => D, kind => K, summary => S, at => At}.

-spec from_map(map()) -> {ok, activity_reported_v1()} | {error, term()}.
from_map(#{activity_id := I, did := D, kind := K, summary := S} = M) ->
    {ok, new(I, D, K, S, maps:get(at, M, erlang:system_time(millisecond)))};
from_map(_) ->
    {error, invalid_activity_reported_event}.
