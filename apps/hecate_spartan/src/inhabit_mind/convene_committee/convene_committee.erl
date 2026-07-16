%%% @doc Convening a committee: a Spartan's act of spawning drones to deliberate.
%%%
%%% This is the public face of the slice. A mind reaches it through the
%%% `convene_committee' tool; it validates the request, guards against a node
%%% convening more committees than it can afford, and hands a well-formed spec to
%%% the committee supervisor. The deliberation itself lives in committee.erl.
%%%
%%% The guard matters: a mind that convened committees without limit could turn a
%%% single fact into an unbounded fan-out of paid LLM calls. A node runs at most
%%% ?MAX_COMMITTEES at once; past that, convening is refused and the mind is told
%%% so, free to speak itself instead.
-module(convene_committee).

-export([convene/1, active_count/0]).

-define(MAX_COMMITTEES, 4).
-define(MAX_DRONES, 5).
-define(MIN_DRONES, 2).

-spec convene(map()) -> {ok, pid()} | {error, term()}.
convene(#{convener := Convener, question := Question} = Spec)
  when is_binary(Convener), Convener =/= <<>>, is_binary(Question), Question =/= <<>> ->
    admit(active_count() < ?MAX_COMMITTEES, Spec);
convene(_Spec) ->
    {error, invalid_committee}.

admit(false, _Spec) ->
    {error, too_many_committees};
admit(true, Spec) ->
    committee_sup:start_committee(clamp_drones(Spec)).

%% @doc How many committees this node is running.
-spec active_count() -> non_neg_integer().
active_count() ->
    committee_sup:count().

%% A committee wants between ?MIN_DRONES and ?MAX_DRONES voices: fewer is not a
%% committee, more is a crowd (and a cost). Default to three when unset.
clamp_drones(Spec) ->
    Spec#{drones => clamp(maps:get(drones, Spec, 3))}.

clamp(N) when is_integer(N) -> max(?MIN_DRONES, min(?MAX_DRONES, N));
clamp(_NotAnInt)            -> 3.
