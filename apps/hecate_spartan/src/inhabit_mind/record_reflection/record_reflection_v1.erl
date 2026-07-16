%%% @doc record_reflection_v1 command — a mind writes a private reflection.
-module(record_reflection_v1).
-behaviour(evoq_command).

-export([new/1, to_map/1, from_map/1, command_type/0]).

-record(record_reflection_v1, {did :: binary(), entry :: binary(), at :: integer()}).

-opaque record_reflection_v1() :: #record_reflection_v1{}.
-export_type([record_reflection_v1/0]).

command_type() -> record_reflection.

new(#{did := D, entry := E} = M) ->
    {ok, #record_reflection_v1{did = D, entry = E,
                               at = maps:get(at, M, erlang:system_time(millisecond))}};
new(_) ->
    {error, missing_fields}.

-spec to_map(record_reflection_v1()) -> map().
to_map(#record_reflection_v1{did = D, entry = E, at = At}) ->
    #{command_type => <<"record_reflection">>, did => D, entry => E, at => At}.

-spec from_map(map()) -> {ok, record_reflection_v1()} | {error, term()}.
from_map(#{did := _, entry := _} = M) -> new(M);
from_map(_) -> {error, invalid_record_reflection_command}.
