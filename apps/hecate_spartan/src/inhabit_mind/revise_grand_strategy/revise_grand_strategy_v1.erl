%%% @doc revise_grand_strategy_v1 command — a mind rewrites its long-horizon plan.
-module(revise_grand_strategy_v1).
-behaviour(evoq_command).

-export([new/1, to_map/1, from_map/1, command_type/0]).

-record(revise_grand_strategy_v1, {did :: binary(), text :: binary(), at :: integer()}).

-opaque revise_grand_strategy_v1() :: #revise_grand_strategy_v1{}.
-export_type([revise_grand_strategy_v1/0]).

command_type() -> revise_grand_strategy.

new(#{did := D, text := T} = M) ->
    {ok, #revise_grand_strategy_v1{did = D, text = T,
                                   at = maps:get(at, M, erlang:system_time(millisecond))}};
new(_) ->
    {error, missing_fields}.

-spec to_map(revise_grand_strategy_v1()) -> map().
to_map(#revise_grand_strategy_v1{did = D, text = T, at = At}) ->
    #{command_type => <<"revise_grand_strategy">>, did => D, text => T, at => At}.

-spec from_map(map()) -> {ok, revise_grand_strategy_v1()} | {error, term()}.
from_map(#{did := _, text := _} = M) -> new(M);
from_map(_) -> {error, invalid_revise_grand_strategy_command}.
