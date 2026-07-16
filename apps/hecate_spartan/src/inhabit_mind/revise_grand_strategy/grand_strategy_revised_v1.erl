%%% @doc grand_strategy_revised_v1 event — a mind rewrote its long-horizon plan.
-module(grand_strategy_revised_v1).
-behaviour(evoq_event).

-export([new/1, to_map/1, from_map/1, event_type/0]).

-record(grand_strategy_revised_v1, {did :: binary(), text :: binary(), at :: integer()}).

-opaque grand_strategy_revised_v1() :: #grand_strategy_revised_v1{}.
-export_type([grand_strategy_revised_v1/0]).

event_type() -> <<"grand_strategy_revised_v1">>.

new(#{did := D, text := T} = M) ->
    #grand_strategy_revised_v1{did = D, text = T,
                               at = maps:get(at, M, erlang:system_time(millisecond))}.

-spec to_map(grand_strategy_revised_v1()) -> map().
to_map(#grand_strategy_revised_v1{did = D, text = T, at = At}) ->
    #{event_type => <<"grand_strategy_revised_v1">>, did => D, text => T, at => At}.

-spec from_map(map()) -> {ok, grand_strategy_revised_v1()} | {error, term()}.
from_map(#{did := _, text := _} = M) -> {ok, new(M)};
from_map(_) -> {error, invalid_grand_strategy_revised_event}.
