%%% @doc record_lesson_v1 command — a mind records a lesson learned.
-module(record_lesson_v1).
-behaviour(evoq_command).

-export([new/1, to_map/1, from_map/1, command_type/0]).

-record(record_lesson_v1, {did :: binary(), lesson :: binary(), at :: integer()}).

-opaque record_lesson_v1() :: #record_lesson_v1{}.
-export_type([record_lesson_v1/0]).

command_type() -> record_lesson.

new(#{did := D, lesson := L} = M) ->
    {ok, #record_lesson_v1{did = D, lesson = L,
                           at = maps:get(at, M, erlang:system_time(millisecond))}};
new(_) ->
    {error, missing_fields}.

-spec to_map(record_lesson_v1()) -> map().
to_map(#record_lesson_v1{did = D, lesson = L, at = At}) ->
    #{command_type => <<"record_lesson">>, did => D, lesson => L, at => At}.

-spec from_map(map()) -> {ok, record_lesson_v1()} | {error, term()}.
from_map(#{did := _, lesson := _} = M) -> new(M);
from_map(_) -> {error, invalid_record_lesson_command}.
