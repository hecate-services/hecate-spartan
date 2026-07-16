%%% @doc charter_amended_v1 event — a mind changed its constitution.
-module(charter_amended_v1).
-behaviour(evoq_event).

-export([new/1, to_map/1, from_map/1, event_type/0]).

-record(charter_amended_v1, {
    did        :: binary(),
    entry_type :: binary(),
    statement  :: binary(),
    derivation :: binary(),
    at         :: integer()
}).

-opaque charter_amended_v1() :: #charter_amended_v1{}.
-export_type([charter_amended_v1/0]).

event_type() -> <<"charter_amended_v1">>.

new(#{did := D, entry_type := T, statement := S} = M) ->
    #charter_amended_v1{
        did = D, entry_type = T, statement = S,
        derivation = maps:get(derivation, M, <<>>),
        at = maps:get(at, M, erlang:system_time(millisecond))}.

-spec to_map(charter_amended_v1()) -> map().
to_map(#charter_amended_v1{did = D, entry_type = T, statement = S,
                           derivation = Dv, at = At}) ->
    #{event_type => <<"charter_amended_v1">>,
      did => D, entry_type => T, statement => S, derivation => Dv, at => At}.

-spec from_map(map()) -> {ok, charter_amended_v1()} | {error, term()}.
from_map(#{did := _, entry_type := _, statement := _} = M) ->
    {ok, new(M)};
from_map(_) ->
    {error, invalid_charter_amended_event}.
