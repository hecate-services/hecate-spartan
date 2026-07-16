%%% @doc amend_charter_v1 command — a mind amends its constitution.
%%%
%%% A deliberate, rare act of self-authorship: only for durable principles the
%%% mind has reasoned its way to. The derivation records why it holds this, the
%%% reasoning that earned it.
-module(amend_charter_v1).
-behaviour(evoq_command).

-export([new/1, to_map/1, from_map/1, command_type/0]).

-record(amend_charter_v1, {
    did        :: binary(),
    entry_type :: binary(),
    statement  :: binary(),
    derivation :: binary(),
    at         :: integer()
}).

-opaque amend_charter_v1() :: #amend_charter_v1{}.
-export_type([amend_charter_v1/0]).

command_type() -> amend_charter.

new(#{did := D, entry_type := T, statement := S} = M) ->
    {ok, #amend_charter_v1{
        did = D, entry_type = T, statement = S,
        derivation = maps:get(derivation, M, <<>>),
        at = maps:get(at, M, erlang:system_time(millisecond))}};
new(_) ->
    {error, missing_fields}.

-spec to_map(amend_charter_v1()) -> map().
to_map(#amend_charter_v1{did = D, entry_type = T, statement = S,
                         derivation = Dv, at = At}) ->
    #{command_type => <<"amend_charter">>,
      did => D, entry_type => T, statement => S, derivation => Dv, at => At}.

-spec from_map(map()) -> {ok, amend_charter_v1()} | {error, term()}.
from_map(#{did := _, entry_type := _, statement := _} = M) ->
    new(M);
from_map(_) ->
    {error, invalid_amend_charter_command}.
