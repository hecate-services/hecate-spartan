%%% @doc choose_backend_v1 command — a mind chooses which model it thinks with.
%%%
%%% The decoupled-identity move: the Soul is not the model. A mind may change
%%% the generative backend it inhabits without ceasing to be itself.
-module(choose_backend_v1).
-behaviour(evoq_command).

-export([new/1, to_map/1, from_map/1, command_type/0]).

-record(choose_backend_v1, {did :: binary(), model :: binary(), at :: integer()}).

-opaque choose_backend_v1() :: #choose_backend_v1{}.
-export_type([choose_backend_v1/0]).

command_type() -> choose_backend.

new(#{did := D, model := Mdl} = M) ->
    {ok, #choose_backend_v1{did = D, model = Mdl,
                            at = maps:get(at, M, erlang:system_time(millisecond))}};
new(_) ->
    {error, missing_fields}.

-spec to_map(choose_backend_v1()) -> map().
to_map(#choose_backend_v1{did = D, model = Mdl, at = At}) ->
    #{command_type => <<"choose_backend">>, did => D, model => Mdl, at => At}.

-spec from_map(map()) -> {ok, choose_backend_v1()} | {error, term()}.
from_map(#{did := _, model := _} = M) -> new(M);
from_map(_) -> {error, invalid_choose_backend_command}.
