%%% @doc lesson_recorded_v1 event — a mind recorded a lesson.
-module(lesson_recorded_v1).
-behaviour(evoq_event).

-export([new/1, to_map/1, from_map/1, event_type/0]).

-record(lesson_recorded_v1, {did :: binary(), lesson :: binary(), at :: integer()}).

-opaque lesson_recorded_v1() :: #lesson_recorded_v1{}.
-export_type([lesson_recorded_v1/0]).

event_type() -> <<"lesson_recorded_v1">>.

new(#{did := D, lesson := L} = M) ->
    #lesson_recorded_v1{did = D, lesson = L,
                        at = maps:get(at, M, erlang:system_time(millisecond))}.

-spec to_map(lesson_recorded_v1()) -> map().
to_map(#lesson_recorded_v1{did = D, lesson = L, at = At}) ->
    #{event_type => <<"lesson_recorded_v1">>, did => D, lesson => L, at => At}.

-spec from_map(map()) -> {ok, lesson_recorded_v1()} | {error, term()}.
from_map(#{did := _, lesson := _} = M) -> {ok, new(M)};
from_map(_) -> {error, invalid_lesson_recorded_event}.
