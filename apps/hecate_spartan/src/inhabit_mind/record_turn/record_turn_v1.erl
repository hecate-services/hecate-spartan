%%% @doc record_turn_v1 command — a mind records one turn of lived experience.
%%%
%%% Every turn is recorded, including silent ones: a choice not to act is a
%%% judgment worth holding. The event is lean — trigger, private thought, the
%%% tools called, and the token cost — never the assembled context, which is
%%% large and reconstructable. Volume is controlled at the trigger, not here.
-module(record_turn_v1).
-behaviour(evoq_command).

-export([new/1, to_map/1, from_map/1, command_type/0]).

-record(record_turn_v1, {
    turn_id :: binary(),
    did     :: binary(),
    heard   :: binary(),
    thought :: binary(),
    actions :: [binary()],
    tokens  :: non_neg_integer(),
    at      :: integer()
}).

-opaque record_turn_v1() :: #record_turn_v1{}.
-export_type([record_turn_v1/0]).

command_type() -> record_turn.

new(#{turn_id := Tid, did := D} = M) ->
    {ok, #record_turn_v1{
        turn_id = Tid, did = D,
        heard   = maps:get(heard, M, <<>>),
        thought = maps:get(thought, M, <<>>),
        actions = maps:get(actions, M, []),
        tokens  = maps:get(tokens, M, 0),
        at      = maps:get(at, M, erlang:system_time(millisecond))}};
new(_) ->
    {error, missing_fields}.

-spec to_map(record_turn_v1()) -> map().
to_map(#record_turn_v1{turn_id = Tid, did = D, heard = H, thought = T,
                       actions = A, tokens = Tok, at = At}) ->
    #{command_type => <<"record_turn">>,
      turn_id => Tid, did => D, heard => H, thought => T,
      actions => A, tokens => Tok, at => At}.

-spec from_map(map()) -> {ok, record_turn_v1()} | {error, term()}.
from_map(#{turn_id := _, did := _} = M) -> new(M);
from_map(_) -> {error, invalid_record_turn_command}.
