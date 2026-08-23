%%% @doc A mind's own tunable parameters: L1 self-modification.
%%%
%%% `evolve_self' (soul:extend_genesis/2) adopts open-ended operating
%%% principles, gated by an adversarial verifier because free text has no
%%% built-in bound. A tunable is the opposite shape: a typed value inside a
%%% fixed, declared range the mind was born with — MINDfulness on or off, how
%%% many memories to recall. The range IS the safety bound, so retuning is
%%% validated mechanically (type + bounds), not by an LLM call.
%%%
%%% Persisted the same way as every other act of self-authorship (soul.erl):
%%% the journal records the act first, then the Tunables.md document is
%%% written — SET, not appended, because a parameter has one current value;
%%% its history of changes lives in the journal (soul:prior/2), not the
%%% document.
-module(mind_tunables).

-export([schema/0, current/1, current/2, retuned/2, retune/3]).

-type id() :: mindfulness | memory_recall_k.
-export_type([id/0]).

%% @doc The declared, bounded knobs a mind may retune about itself. Adding one
%% here and wiring its read site is the whole surface of a new tunable.
-spec schema() -> [map()].
schema() ->
    [#{id => mindfulness, type => boolean, default => true,
       description => <<"Draft-then-verify a second reasoning pass before acting.">>},
     #{id => memory_recall_k, type => integer, min => 0, max => 20, default => 2,
       description => <<"How many past memories to recall into context each turn.">>}].

%% @doc This mind's current value for every declared knob: its own retune
%% where it made one, the schema default otherwise.
-spec current(binary()) -> #{id() => boolean() | integer()}.
current(Did) ->
    maps:from_list([{Id, resolved(retuned(Did, Id), Default)}
                    || #{id := Id, default := Default} <- schema()]).

resolved({ok, Value}, _Default) -> Value;
resolved(not_set, Default)      -> Default.

%% @doc This mind's current value for one knob.
-spec current(binary(), id()) -> boolean() | integer().
current(Did, Id) ->
    maps:get(Id, current(Did)).

%% @doc Whether this mind has EXPLICITLY retuned one knob, distinct from
%% current/2 (which resolves to the schema default when it has not). Lets a
%% caller with its own fallback (e.g. a node-wide env var) rank that fallback
%% ABOVE the schema default but BELOW a mind's own explicit choice.
-spec retuned(binary(), id()) -> {ok, term()} | not_set.
retuned(Did, Id) ->
    explicit(maps:get(Id, parse(soul:read_area(Did, tunables)), undefined)).

explicit(undefined) -> not_set;
explicit(Value)     -> {ok, Value}.

%% @doc Propose a new value for one declared knob. An unknown id or a value
%% outside its declared type/range is rejected without being written
%% anywhere; takes effect on the very next read (no reboot).
-spec retune(binary(), id(), term()) -> {ok, term()} | {error, term()}.
retune(Did, Id, Value) ->
    apply_valid(coerce(find(Id, schema()), Id, Value), Did, Id).

find(Id, Schema) ->
    one([S || #{id := I} = S <- Schema, I =:= Id]).

one([S]) -> S;
one([])  -> undefined.

coerce(undefined, Id, _Value) ->
    {error, {unknown_tunable, Id}};
coerce(#{type := boolean}, _Id, V) when is_boolean(V) ->
    {ok, V};
coerce(#{type := boolean}, _Id, V) ->
    {error, {not_a_boolean, V}};
coerce(#{type := integer, min := Min, max := Max}, _Id, V) when is_integer(V) ->
    in_range(V, Min, Max);
coerce(#{type := integer}, _Id, V) ->
    {error, {not_an_integer, V}}.

in_range(V, Min, Max) when V >= Min, V =< Max ->
    {ok, V};
in_range(V, Min, Max) ->
    {error, {out_of_range, V, {Min, Max}}}.

apply_valid({ok, Value}, Did, Id) ->
    All = current(Did),
    ok = soul:set_tunables(Did, render(All#{Id => Value})),
    {ok, Value};
apply_valid({error, _} = E, _Did, _Id) ->
    E.

%% --- rendering / parsing (Tunables.md: one "id: value" line per knob) ---

render(Values) ->
    iolist_to_binary([render_line(Id, maps:get(Id, Values)) || #{id := Id} <- schema()]).

render_line(Id, V) ->
    [atom_to_binary(Id, utf8), <<": ">>, render_value(V), <<"\n">>].

render_value(V) when is_boolean(V) -> atom_to_binary(V, utf8);
render_value(V) when is_integer(V) -> integer_to_binary(V).

parse(Text) ->
    Lines = binary:split(Text, <<"\n">>, [global]),
    maps:from_list(lists:filtermap(fun parse_line/1, Lines)).

parse_line(Line) ->
    known(binary:split(Line, <<": ">>)).

known([K, V]) -> with_id(existing_id(K), V);
known(_Other) -> false.

%% `binary_to_existing_atom' rather than `binary_to_atom': Tunables.md is
%% single-writer (this module) but, like every Soul area, a hand-edit must
%% survive without crashing the mind — never mint a new atom from file
%% content, only recognize the ids this module already declared.
existing_id(K) ->
    try binary_to_existing_atom(K, utf8) catch _:_ -> undefined end.

with_id(undefined, _V) -> false;
with_id(Id, V)         -> with_spec(find(Id, schema()), Id, V).

with_spec(undefined, _Id, _V) -> false;
with_spec(Spec, Id, V)        -> decoded(decode(Spec, V), Id).

decoded(undefined, _Id) -> false;
decoded(Value, Id)      -> {true, {Id, Value}}.

decode(#{type := boolean}, <<"true">>)  -> true;
decode(#{type := boolean}, <<"false">>) -> false;
decode(#{type := boolean}, _Other)      -> undefined;
decode(#{type := integer}, V)           -> decode_int(string:to_integer(V)).

decode_int({I, <<>>}) when is_integer(I) -> I;
decode_int(_NotAClean_Integer)           -> undefined.
