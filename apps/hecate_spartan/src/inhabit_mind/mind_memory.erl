%%% @doc A mind's long-term memory, by lexical recall.
%%%
%%% No embeddings, no vector index, no external embedder. A mind remembers the
%%% turns it lived through and, when a new stimulus arrives, recalls the ones
%%% whose words most overlap it: "have I faced something like this before?"
%%%
%%% This is deliberately sovereign and in-process. It replaces the earlier
%%% embed-and-vector-search LTM (hecate-embed / hecate-vector / the hecate-embedder
%%% mesh service), which needed an ONNX runtime the beam Celerons cannot run
%%% (AVX2). It pairs with the memory faculty's Sleep Cycle: the CONSOLIDATED gist
%%% of a life is always in context (CMOs, MSOs), and this provides targeted recall
%%% of specific past turns by word overlap. Less semantically precise than
%%% embeddings; simpler, local, and dependency-free. See docs/DESIGN_MIND_FACULTIES.
%%%
%%% Every operation is pure and best-effort; there is nothing to fail.
-module(mind_memory).

-export([open/1, remember/2, recall/3, seed/2, size/1]).

%% An entry keeps the display text and its token set (computed once at insert).
-type mem() :: #{did := binary(), entries := [{binary(), [binary()]}]}.
-export_type([mem/0]).

-spec open(binary()) -> {ok, mem()}.
open(Did) when is_binary(Did) ->
    {ok, #{did => Did, entries => []}}.

-spec remember(mem(), binary()) -> mem().
remember(#{entries := Es} = Mem, Text) when is_binary(Text), Text =/= <<>> ->
    Mem#{entries => Es ++ [{Text, tokens(Text)}]};
remember(Mem, _Text) ->
    Mem.

%% @doc The K remembered texts whose words most overlap the query, best first.
%% Zero-overlap entries are never returned; an empty query recalls nothing.
-spec recall(mem(), binary(), pos_integer()) -> [binary()].
recall(#{entries := Es}, Query, K)
  when is_binary(Query), Query =/= <<>>, is_integer(K), K > 0 ->
    QTokens = tokens(Query),
    Scored  = [{score(QTokens, ETokens), Text} || {Text, ETokens} <- Es],
    Hits    = lists:sort(fun({A, _}, {B, _}) -> A >= B end,
                         [Pair || {S, _} = Pair <- Scored, S > 0]),
    [Text || {_S, Text} <- lists:sublist(Hits, K)];
recall(_Mem, _Query, _K) ->
    [].

%% @doc Bulk-remember (boot seeding from replayed history).
-spec seed(mem(), [binary()]) -> mem().
seed(Mem, Texts) when is_list(Texts) ->
    lists:foldl(fun(T, M) -> remember(M, T) end, Mem, Texts).

-spec size(mem()) -> non_neg_integer().
size(#{entries := Es}) -> length(Es).

%% --- lexical helpers ---

%% Lowercase, split on non-alphanumerics, drop very short words, dedup.
tokens(Text) ->
    Words = re:split(string:lowercase(Text), <<"[^a-z0-9]+">>, [{return, binary}]),
    lists:usort([W || W <- Words, byte_size(W) > 2]).

%% Overlap: how many of the query's tokens appear in the entry.
score(QTokens, ETokens) ->
    length([W || W <- QTokens, lists:member(W, ETokens)]).
