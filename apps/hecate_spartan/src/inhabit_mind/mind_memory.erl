%%% @doc A mind's long-term semantic memory.
%%%
%%% The chronicle is a small recency window (the last few turns); this is the
%%% rest, recalled by MEANING rather than recency. When a stimulus arrives the
%%% mind asks "have I faced something like this before?", and the turns it lived
%%% through that are semantically nearest surface into its context, however long
%%% ago they happened.
%%%
%%% It owns only the memory POLICY. The two capabilities it composes live in
%%% their own libraries: `hecate_embed' turns text into a vector (a real ONNX
%%% embedder in production, a deterministic stub in dev), and `hecate_vector' is
%%% the mind's own nearest-neighbour index. Embeddings are derived, model-
%%% specific data, so they are never domain facts: this index is a read-model,
%%% seeded at boot from the mind's replayed turn history and grown as it lives.
%%%
%%% Every operation is best-effort. A mind whose embedder or index is momentarily
%%% unavailable simply recalls nothing that turn; memory must never crash a turn.
-module(mind_memory).

-export([open/1, remember/2, recall/3, seed/2, size/1]).

%% multilingual-e5-small, and the stub, both produce 384-dim vectors.
-define(DIM, 384).

-type mem() :: #{did := binary(), index := term(), texts := #{binary() => binary()}}.
-export_type([mem/0]).

%% @doc Open a mind's memory: this mind's own vector index (named by its DID).
%% Empty to start; the caller seeds it. Embedding is done by spartan_embed
%% (mesh or http), so no model handle is held here.
-spec open(binary()) -> {ok, mem()} | {error, term()}.
open(Did) when is_binary(Did) ->
    with_index(Did, catch open_index(Did)).

with_index(Did, {ok, Index}) ->
    {ok, #{did => Did, index => Index, texts => #{}}};
with_index(_Did, _Index) ->
    {error, memory_unavailable}.

open_index(Did) ->
    hecate_vector:open(index_name(Did), #{dim => ?DIM}).

%% @doc Store one memory: embed it as a passage and add it to the index, keeping
%% the display text alongside. Returns the (possibly unchanged) memory handle.
-spec remember(mem(), binary()) -> mem().
remember(#{index := Index, texts := Texts} = Mem, Text)
  when is_binary(Text), Text =/= <<>> ->
    add_embedding(Mem, Index, Texts, catch spartan_embed:passage(Text), Text);
remember(Mem, _Text) ->
    Mem.

add_embedding(Mem, Index, Texts, {ok, Vec}, Text) ->
    Id = new_id(),
    _ = catch hecate_vector:add(Index, Id, Vec),
    Mem#{texts => Texts#{Id => Text}};
add_embedding(Mem, _Index, _Texts, _Failed, _Text) ->
    Mem.

%% @doc Recall the K memories nearest in meaning to a query, as their texts.
%% Never raises: any failure yields no memories.
-spec recall(mem(), binary(), pos_integer()) -> [binary()].
recall(#{index := Index, texts := Texts}, Query, K)
  when is_binary(Query), Query =/= <<>>, is_integer(K), K > 0 ->
    search_texts(catch spartan_embed:query(Query), Index, Texts, K);
recall(_Mem, _Query, _K) ->
    [].

search_texts({ok, QVec}, Index, Texts, K) ->
    hits_to_texts(catch hecate_vector:search(Index, QVec, K), Texts);
search_texts(_Failed, _Index, _Texts, _K) ->
    [].

hits_to_texts({ok, Hits}, Texts) when is_list(Hits) ->
    lists:filtermap(fun({Id, _Score}) -> lookup(Id, Texts) end, Hits);
hits_to_texts(_Other, _Texts) ->
    [].

lookup(Id, Texts) ->
    case maps:find(Id, Texts) of
        {ok, Text} -> {true, Text};
        error      -> false
    end.

%% @doc Bulk-remember a list of texts (boot seeding from replayed history).
-spec seed(mem(), [binary()]) -> mem().
seed(Mem, Texts) when is_list(Texts) ->
    lists:foldl(fun(T, M) -> remember(M, T) end, Mem, Texts).

-spec size(mem()) -> non_neg_integer().
size(#{texts := Texts}) -> map_size(Texts).

%% One stable index name per mind. A node inhabits a handful of minds, so the
%% handful of atoms this mints is bounded.
index_name(Did) ->
    list_to_atom("mind_mem_" ++ integer_to_list(erlang:phash2(Did))).

new_id() ->
    binary:encode_hex(crypto:strong_rand_bytes(16), lowercase).
