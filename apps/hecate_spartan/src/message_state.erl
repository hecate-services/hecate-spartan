%%% @doc State module for the message aggregate.
%%%
%%% A message is a one-event stream (routed once, for provenance). There is no
%%% state to fold, so this is deliberately trivial.
-module(message_state).
-behaviour(evoq_state).

-export([new/1, apply_event/2, to_map/1]).

new(_AggregateId) -> #{}.

apply_event(State, _Event) -> State.

to_map(State) -> State.
