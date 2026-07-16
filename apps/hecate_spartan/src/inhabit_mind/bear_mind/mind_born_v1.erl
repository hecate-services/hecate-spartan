%%% @doc mind_born_v1 event — a mind came into being.
%%%
%%% The genesis event of a Soul stream. Carries the PUBLIC identity (did,
%%% pubkey), the name, the genesis version it was born into, and the founding
%%% brief. The private key is never here; it is sealed to disk separately as
%%% secret material.
-module(mind_born_v1).
-behaviour(evoq_event).

-export([new/1, to_map/1, from_map/1, event_type/0]).

-record(mind_born_v1, {
    did             :: binary(),
    name            :: binary(),
    founding_brief  :: binary(),
    genesis_version :: binary(),
    pubkey          :: binary(),
    born_at         :: integer()
}).

-opaque mind_born_v1() :: #mind_born_v1{}.
-export_type([mind_born_v1/0]).

event_type() -> <<"mind_born_v1">>.

new(#{did := D, name := N, founding_brief := B, pubkey := P} = M) ->
    #mind_born_v1{
        did = D, name = N, founding_brief = B, pubkey = P,
        genesis_version = maps:get(genesis_version, M, <<"0">>),
        born_at = maps:get(born_at, M, erlang:system_time(millisecond))}.

-spec to_map(mind_born_v1()) -> map().
to_map(#mind_born_v1{did = D, name = N, founding_brief = B,
                     genesis_version = G, pubkey = P, born_at = At}) ->
    #{event_type => <<"mind_born_v1">>,
      did => D, name => N, founding_brief => B,
      genesis_version => G, pubkey => P, born_at => At}.

-spec from_map(map()) -> {ok, mind_born_v1()} | {error, term()}.
from_map(#{did := _, name := _, founding_brief := _, pubkey := _} = M) ->
    {ok, new(M)};
from_map(_) ->
    {error, invalid_mind_born_event}.
