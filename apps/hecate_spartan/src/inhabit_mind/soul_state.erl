%%% @doc State module for the Soul aggregate. Owns the record and the fold.
%%%
%%% The Soul is the persistent identity kernel: who a mind is, distinct from
%%% the generative backend it happens to think with. Every act of
%%% self-authorship is an event; this module folds those events into the
%%% current #soul{}. A mind rebuilds its Soul by replaying its stream through
%%% here, then keeps the result cached in its gen_server.
-module(soul_state).
-behaviour(evoq_state).

-include("hecate_spartan_soul.hrl").

-export([new/1, apply_event/2, to_map/1]).

-type state() :: #soul{}.
-export_type([state/0]).

-spec new(binary()) -> state().
new(_AggregateId) ->
    #soul{status = 0}.

-spec apply_event(state(), map()) -> state().
apply_event(State, #{event_type := EventType} = Event) ->
    do_apply(EventType, State, Event);
apply_event(State, _) ->
    State.

%% ===================================================================
%% Event application
%% ===================================================================

do_apply(<<"mind_born_v1">>, S, E) ->
    S#soul{
        did             = gf(did, E),
        name            = gf(name, E),
        genesis_version = gf(genesis_version, E),
        founding_brief  = gf(founding_brief, E),
        born_at         = gf(born_at, E),
        status          = S#soul.status bor ?SOUL_BORN
    };
do_apply(<<"charter_amended_v1">>, S, E) ->
    Entry = #{entry_type => gf(entry_type, E),
              statement  => gf(statement, E),
              derivation => gf(derivation, E),
              at         => gf(at, E)},
    S#soul{charter = S#soul.charter ++ [Entry]};
do_apply(<<"lesson_recorded_v1">>, S, E) ->
    S#soul{lessons = S#soul.lessons ++ [#{lesson => gf(lesson, E), at => gf(at, E)}]};
do_apply(<<"reflection_recorded_v1">>, S, E) ->
    S#soul{journal = S#soul.journal ++ [#{entry => gf(entry, E), at => gf(at, E)}]};
do_apply(<<"grand_strategy_revised_v1">>, S, E) ->
    S#soul{grand_strategy = gf(text, E)};
do_apply(<<"working_memory_revised_v1">>, S, E) ->
    S#soul{working_memory = gf(text, E)};
do_apply(<<"backend_chosen_v1">>, S, E) ->
    S#soul{backend = gf(model, E)};
do_apply(_Unknown, S, _E) ->
    S.

-spec to_map(state()) -> map().
to_map(#soul{} = S) ->
    #{did             => S#soul.did,
      name            => S#soul.name,
      genesis_version => S#soul.genesis_version,
      founding_brief  => S#soul.founding_brief,
      born_at         => S#soul.born_at,
      charter         => S#soul.charter,
      lessons         => S#soul.lessons,
      journal         => S#soul.journal,
      grand_strategy  => S#soul.grand_strategy,
      working_memory  => S#soul.working_memory,
      backend         => S#soul.backend,
      status          => S#soul.status}.

%% Event fields may come back keyed by atom or binary depending on the
%% serialization round-trip; accept either.
gf(AtomKey, Event) ->
    maps:get(AtomKey, Event, maps:get(atom_to_binary(AtomKey, utf8), Event, undefined)).
