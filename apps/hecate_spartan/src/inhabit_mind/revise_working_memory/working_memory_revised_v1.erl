%%% @doc working_memory_revised_v1 event — a mind rewrote its short-horizon focus.
-module(working_memory_revised_v1).
-behaviour(evoq_event).

-export([new/1, to_map/1, from_map/1, event_type/0]).

-record(working_memory_revised_v1, {did :: binary(), text :: binary(), at :: integer()}).

-opaque working_memory_revised_v1() :: #working_memory_revised_v1{}.
-export_type([working_memory_revised_v1/0]).

event_type() -> <<"working_memory_revised_v1">>.

new(#{did := D, text := T} = M) ->
    #working_memory_revised_v1{did = D, text = T,
                               at = maps:get(at, M, erlang:system_time(millisecond))}.

-spec to_map(working_memory_revised_v1()) -> map().
to_map(#working_memory_revised_v1{did = D, text = T, at = At}) ->
    #{event_type => <<"working_memory_revised_v1">>, did => D, text => T, at => At}.

-spec from_map(map()) -> {ok, working_memory_revised_v1()} | {error, term()}.
from_map(#{did := _, text := _} = M) -> {ok, new(M)};
from_map(_) -> {error, invalid_working_memory_revised_event}.
