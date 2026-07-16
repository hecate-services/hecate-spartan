%%% @doc revise_working_memory_v1 command — a mind rewrites its short-horizon focus.
-module(revise_working_memory_v1).
-behaviour(evoq_command).

-export([new/1, to_map/1, from_map/1, command_type/0]).

-record(revise_working_memory_v1, {did :: binary(), text :: binary(), at :: integer()}).

-opaque revise_working_memory_v1() :: #revise_working_memory_v1{}.
-export_type([revise_working_memory_v1/0]).

command_type() -> revise_working_memory.

new(#{did := D, text := T} = M) ->
    {ok, #revise_working_memory_v1{did = D, text = T,
                                   at = maps:get(at, M, erlang:system_time(millisecond))}};
new(_) ->
    {error, missing_fields}.

-spec to_map(revise_working_memory_v1()) -> map().
to_map(#revise_working_memory_v1{did = D, text = T, at = At}) ->
    #{command_type => <<"revise_working_memory">>, did => D, text => T, at => At}.

-spec from_map(map()) -> {ok, revise_working_memory_v1()} | {error, term()}.
from_map(#{did := _, text := _} = M) -> new(M);
from_map(_) -> {error, invalid_revise_working_memory_command}.
