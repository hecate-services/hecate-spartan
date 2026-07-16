%%% @doc turn_taken_v1 event — a mind lived one turn.
%%%
%%% Private to the mind (its chronicle), never emitted to the mesh. One stream
%%% per turn (turn-{id}), replayed by type at boot like the agora feed, so a
%%% mind reconstructs its recent history without loading one ever-growing
%%% stream.
-module(turn_taken_v1).
-behaviour(evoq_event).

-export([new/1, to_map/1, from_map/1, event_type/0]).
-export([replay/0]).

%% The chronicle is a window at the edge and the log behind it; the mind keeps
%% only a recent window in mind, so a bounded replay is enough.
-define(REPLAY_BATCH, 500).

-record(turn_taken_v1, {
    turn_id :: binary(),
    did     :: binary(),
    heard   :: binary(),
    thought :: binary(),
    actions :: [binary()],
    tokens  :: non_neg_integer(),
    at      :: integer()
}).

-opaque turn_taken_v1() :: #turn_taken_v1{}.
-export_type([turn_taken_v1/0]).

event_type() -> <<"turn_taken_v1">>.

new(#{turn_id := Tid, did := D} = M) ->
    #turn_taken_v1{
        turn_id = Tid, did = D,
        heard   = maps:get(heard, M, <<>>),
        thought = maps:get(thought, M, <<>>),
        actions = maps:get(actions, M, []),
        tokens  = maps:get(tokens, M, 0),
        at      = maps:get(at, M, erlang:system_time(millisecond))}.

-spec to_map(turn_taken_v1()) -> map().
to_map(#turn_taken_v1{turn_id = Tid, did = D, heard = H, thought = T,
                      actions = A, tokens = Tok, at = At}) ->
    #{event_type => <<"turn_taken_v1">>,
      turn_id => Tid, did => D, heard => H, thought => T,
      actions => A, tokens => Tok, at => At}.

-spec from_map(map()) -> {ok, turn_taken_v1()} | {error, term()}.
from_map(#{turn_id := _, did := _} = M) -> {ok, new(M)};
from_map(_) -> {error, invalid_turn_taken_event}.

%% @doc Every mind's turns on this node, flattened to event maps. The caller
%% filters to its own DID and windows. Same rationale as the agora feed replay:
%% the store subscription replays the log once, at store start, before the
%% supervision tree exists, so no projection is registered to hear it.
-spec replay() -> [map()].
replay() ->
    replay_from(application:get_env(hecate_spartan, event_store_id)).

replay_from(undefined) ->
    [];
replay_from({ok, StoreId}) ->
    case catch evoq_event_store:read_events_by_types(
                 StoreId, [event_type()], ?REPLAY_BATCH) of
        {ok, Events} when is_list(Events) -> Events;
        _Unavailable                      -> []
    end.
