%%% @doc reflection_recorded_v1 event — a mind wrote a private reflection.
-module(reflection_recorded_v1).
-behaviour(evoq_event).

-export([new/1, to_map/1, from_map/1, event_type/0]).

-record(reflection_recorded_v1, {did :: binary(), entry :: binary(), at :: integer()}).

-opaque reflection_recorded_v1() :: #reflection_recorded_v1{}.
-export_type([reflection_recorded_v1/0]).

event_type() -> <<"reflection_recorded_v1">>.

new(#{did := D, entry := E} = M) ->
    #reflection_recorded_v1{did = D, entry = E,
                            at = maps:get(at, M, erlang:system_time(millisecond))}.

-spec to_map(reflection_recorded_v1()) -> map().
to_map(#reflection_recorded_v1{did = D, entry = E, at = At}) ->
    #{event_type => <<"reflection_recorded_v1">>, did => D, entry => E, at => At}.

-spec from_map(map()) -> {ok, reflection_recorded_v1()} | {error, term()}.
from_map(#{did := _, entry := _} = M) -> {ok, new(M)};
from_map(_) -> {error, invalid_reflection_recorded_event}.
