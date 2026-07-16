%%% @doc bear_mind_v1 command — an instantiator gives a mind its genesis.
%%%
%%% Birth is an instantiation act, not a self-authored one: the instantiator
%%% (the supervisor at first boot) supplies the name, the genesis version, and
%%% the founding brief. The brief is the use-case-agnosticism seam — a mission
%%% reaches a mind here as CONTEXT, not command, carried as data on the event
%%% rather than baked into the mind's code.
-module(bear_mind_v1).
-behaviour(evoq_command).

-export([new/1, to_map/1, from_map/1, command_type/0]).

-record(bear_mind_v1, {
    did             :: binary(),
    name            :: binary(),
    founding_brief  :: binary(),
    genesis_version :: binary(),
    pubkey          :: binary(),
    born_at         :: integer()
}).

-opaque bear_mind_v1() :: #bear_mind_v1{}.
-export_type([bear_mind_v1/0]).

command_type() -> bear_mind.

new(#{did := D, name := N, founding_brief := B, pubkey := P} = M) ->
    {ok, #bear_mind_v1{
        did = D, name = N, founding_brief = B, pubkey = P,
        genesis_version = maps:get(genesis_version, M, <<"0">>),
        born_at = maps:get(born_at, M, erlang:system_time(millisecond))}};
new(_) ->
    {error, missing_fields}.

-spec to_map(bear_mind_v1()) -> map().
to_map(#bear_mind_v1{did = D, name = N, founding_brief = B,
                     genesis_version = G, pubkey = P, born_at = At}) ->
    #{command_type => <<"bear_mind">>,
      did => D, name => N, founding_brief => B,
      genesis_version => G, pubkey => P, born_at => At}.

-spec from_map(map()) -> {ok, bear_mind_v1()} | {error, term()}.
from_map(#{did := _, name := _, founding_brief := _, pubkey := _} = M) ->
    new(M);
from_map(_) ->
    {error, invalid_bear_mind_command}.
