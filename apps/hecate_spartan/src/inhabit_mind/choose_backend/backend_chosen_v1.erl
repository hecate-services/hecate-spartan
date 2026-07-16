%%% @doc backend_chosen_v1 event — a mind chose which model it thinks with.
-module(backend_chosen_v1).
-behaviour(evoq_event).

-export([new/1, to_map/1, from_map/1, event_type/0]).

-record(backend_chosen_v1, {did :: binary(), model :: binary(), at :: integer()}).

-opaque backend_chosen_v1() :: #backend_chosen_v1{}.
-export_type([backend_chosen_v1/0]).

event_type() -> <<"backend_chosen_v1">>.

new(#{did := D, model := Mdl} = M) ->
    #backend_chosen_v1{did = D, model = Mdl,
                       at = maps:get(at, M, erlang:system_time(millisecond))}.

-spec to_map(backend_chosen_v1()) -> map().
to_map(#backend_chosen_v1{did = D, model = Mdl, at = At}) ->
    #{event_type => <<"backend_chosen_v1">>, did => D, model => Mdl, at => At}.

-spec from_map(map()) -> {ok, backend_chosen_v1()} | {error, term()}.
from_map(#{did := _, model := _} = M) -> {ok, new(M)};
from_map(_) -> {error, invalid_backend_chosen_event}.
