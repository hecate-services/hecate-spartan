%%% @doc A mind's long-term memory: A-Mem — a linked, semantic store.
%%%
%%% Gene Sher's LTM is not a flat list but a Zettelkasten-inspired graph: when a
%%% memory is stored it is LINKED to its nearest neighbours, and recall follows
%%% those chains, so remembering one thing surfaces what it connects to. This is
%%% the BEAM-native realization, restored now that a local Ollama gives us
%%% embeddings again — the semantic recall some hardware could not run.
%%%
%%%   remember -> embed (via `embedder') -> link to nearest neighbours -> store.
%%%   recall   -> embed the query -> cosine seeds -> FOLLOW LINKS -> re-rank -> top-K.
%%%   evolve   -> on the sleep cadence, the LLM re-links one memory from its
%%%               cosine candidates (agentic linking), reciprocally.
%%%
%%% Links start as cosine nearest-neighbour (cheap, immediate) and are refined by
%%% `evolve/2' — Gene's LLM-driven A-Mem linking — one memory per sleep window.
%%%
%%% Every entry also keeps a lexical token set, so when the embedder is
%%% unreachable the mind falls back to word-overlap recall — it loses semantic
%%% precision, never its memory. Auto-injection: spartan_mind recalls against
%%% every stimulus and injects the hits into the frontier, so the mind recalls
%%% the relevant past without having to ask. All pure + best-effort.
-module(mind_memory).

-export([open/1, open/2, remember/2, recall/3, seed/2, size/1, save/1, evolve/2]).

%% A new memory links to at most this many nearest neighbours, each above the
%% similarity threshold; recall follows those links one hop out from a seed hit.
-define(LINK_MAX, 5).
-define(LINK_THRESHOLD, 0.55).

%% Evolution candidate net: show the LLM up to CAND_MAX nearest memories above a
%% loose floor, so it has real choice (wider than the store-time cosine links).
-define(CAND_MAX, 8).
-define(CAND_FLOOR, 0.30).

-type entry() :: #{id := binary(), text := binary(), tokens := [binary()],
                   vec := [float()] | undefined, links := [binary()],
                   evolved => boolean()}.
-type reason_fun() :: fun(([map()]) -> {ok, binary()} | error).
-type mem() :: #{did := binary(), dir := binary() | undefined,
                 entries := #{binary() => entry()}}.
-export_type([mem/0]).

%% In-memory only (ephemeral / tests): no data dir, save/1 is a no-op.
-spec open(binary()) -> {ok, mem()}.
open(Did) when is_binary(Did) ->
    open(Did, undefined).

%% Durable: load the persisted store from disk (whole life, with vectors and
%% links, so a restart does NOT re-embed) and remember its data dir so save/1 can
%% write it back. A brand-new mind loads an empty store and is seeded from STM.
-spec open(binary(), binary() | undefined) -> {ok, mem()}.
open(Did, undefined) when is_binary(Did) ->
    {ok, #{did => Did, dir => undefined, entries => #{}}};
open(Did, DataDir) when is_binary(Did), is_binary(DataDir) ->
    {ok, #{did => Did, dir => DataDir, entries => load(path(DataDir, Did))}}.

%% @doc Persist the store atomically (tmp + rename), like the memory_store tiers.
%% Best-effort: an ephemeral (dir=undefined) store persists nothing.
-spec save(mem()) -> ok.
save(#{dir := undefined}) ->
    ok;
save(#{dir := DataDir, did := Did, entries := Es}) ->
    Path = path(DataDir, Did),
    ok = filelib:ensure_dir(Path),
    Tmp = <<Path/binary, ".tmp">>,
    ok = file:write_file(Tmp, term_to_binary(Es)),
    file:rename(Tmp, Path).

load(Path) ->
    interpret_load(file:read_file(Path)).

interpret_load({ok, Bin}) ->
    safe_terms(catch binary_to_term(Bin));
interpret_load(_Absent) ->
    #{}.

safe_terms(Es) when is_map(Es) -> Es;
safe_terms(_Corrupt)          -> #{}.

path(DataDir, Did) ->
    Id = binary:encode_hex(binary:part(crypto:hash(sha256, Did), 0, 16), lowercase),
    iolist_to_binary(filename:join([DataDir, <<"ltm">>, <<Id/binary, ".term">>])).

-spec remember(mem(), binary()) -> mem().
remember(#{entries := Es} = Mem, Text) when is_binary(Text), Text =/= <<>> ->
    store(maps:is_key(id(Text), Es), Text, Mem);
remember(Mem, _Text) ->
    Mem.

%% Dedup by text hash: the same lived turn is remembered once.
store(true, _Text, Mem) ->
    Mem;
store(false, Text, #{entries := Es} = Mem) ->
    Vec = vec_of(embedder:embed(Text, passage)),
    Entry = #{id => id(Text), text => Text, tokens => tokens(Text),
              vec => Vec, links => link_to(Vec, Es), evolved => false},
    Mem#{entries => Es#{id(Text) => Entry}}.

vec_of({ok, V}) -> V;
vec_of(error)   -> undefined.

%% A-Mem linking: link the new memory to its nearest existing neighbours above
%% the threshold. No embedding (embedder down) -> no links this time; the entry
%% still stores and is lexically recallable.
link_to(undefined, _Es) ->
    [];
link_to(Vec, Es) ->
    Scored = [{cosine(Vec, V), Id}
              || #{id := Id, vec := V} <- maps:values(Es), V =/= undefined],
    [Id || {S, Id} <- topn(Scored, ?LINK_MAX), S >= ?LINK_THRESHOLD].

-spec recall(mem(), binary(), pos_integer()) -> [binary()].
recall(#{entries := Es}, Query, K)
  when is_binary(Query), Query =/= <<>>, is_integer(K), K > 0 ->
    retrieve(embedder:embed(Query, query), Es, Query, K);
recall(_Mem, _Query, _K) ->
    [].

retrieve({ok, QVec}, Es, Query, K) ->
    semantic(vectored(Es), QVec, Es, Query, K);
retrieve(error, Es, Query, K) ->
    lexical(Es, Query, K).

%% Nothing embedded yet -> lexical; otherwise cosine seeds, follow their links one
%% hop, and re-rank the union by similarity to the query.
semantic([], _QVec, Es, Query, K) ->
    lexical(Es, Query, K);
semantic(Vectored, QVec, Es, _Query, K) ->
    Seeds = [E || {_S, E} <- topn([{cosine(QVec, maps:get(vec, E)), E} || E <- Vectored], K)],
    Expanded = follow_chains(Seeds, Es),
    Ranked = topn([{cosine(QVec, maps:get(vec, E)), E} || E <- Expanded], K),
    [maps:get(text, E) || {_S, E} <- Ranked].

%% Chain following: a seed hit plus everything one link out from it (unique,
%% embedded so it can be re-ranked).
follow_chains(Seeds, Es) ->
    SeedIds = [maps:get(id, E) || E <- Seeds],
    LinkedIds = lists:append([maps:get(links, E, []) || E <- Seeds]),
    Ids = lists:usort(SeedIds ++ LinkedIds),
    [maps:get(I, Es) || I <- Ids, present_and_vectored(I, Es)].

present_and_vectored(Id, Es) ->
    maps:is_key(Id, Es) andalso maps:get(vec, maps:get(Id, Es)) =/= undefined.

vectored(Es) ->
    [E || #{vec := V} = E <- maps:values(Es), V =/= undefined].

%% Lexical fallback: word overlap, the sovereign path when the embedder is dark.
lexical(Es, Query, K) ->
    QTokens = tokens(Query),
    Scored = [{score(QTokens, maps:get(tokens, E)), maps:get(text, E)}
              || E <- maps:values(Es)],
    [Text || {S, Text} <- topn(Scored, K), S > 0].

-spec seed(mem(), [binary()]) -> mem().
seed(Mem, Texts) when is_list(Texts) ->
    lists:foldl(fun(T, M) -> remember(M, T) end, Mem, Texts).

-spec size(mem()) -> non_neg_integer().
size(#{entries := Es}) -> maps:size(Es).

%% @doc LLM-driven A-Mem evolution — Gene's agentic linking. A stored memory's
%% links are cosine nearest-neighbour at first; evolution shows the LLM one such
%% memory and its nearest candidates and lets it choose which are GENUINELY
%% related (same topic, entity, or causal thread), richer than raw geometry. The
%% chosen neighbours gain a reciprocal back-link (Zettelkasten bidirectionality).
%%
%% ONE memory per call, driven off the sleep cadence by the caller, so it costs a
%% single small LLM call per consolidation window — not one per turn. No backend,
%% no candidates, or an unparseable reply -> the memory stays unevolved with its
%% cosine links intact and is retried next cadence (never a regression).
-spec evolve(mem(), reason_fun()) -> mem().
evolve(#{entries := Es} = Mem, ReasonFun) when is_function(ReasonFun, 1) ->
    evolve_one(next_unevolved(Es), Mem, ReasonFun).

evolve_one(none, Mem, _ReasonFun) ->
    Mem;
evolve_one({ok, Entry}, Mem, ReasonFun) ->
    link_by_llm(candidates(Entry, Mem), Entry, Mem, ReasonFun).

%% Oldest unevolved, vectored memory (deterministic by id): each cadence drains
%% one more, so the backlog is worked through and re-runs are stable.
next_unevolved(Es) ->
    Sorted = lists:sort(fun(A, B) -> maps:get(id, A) =< maps:get(id, B) end,
                        maps:values(Es)),
    first([E || E <- Sorted,
                maps:get(vec, E) =/= undefined,
                not maps:get(evolved, E, false)]).

first([])      -> none;
first([E | _]) -> {ok, E}.

candidates(#{id := Id, vec := Vec}, #{entries := Es}) ->
    Scored = [{cosine(Vec, V), E}
              || #{id := Oid, vec := V} = E <- maps:values(Es),
                 Oid =/= Id, V =/= undefined],
    [E || {S, E} <- topn(Scored, ?CAND_MAX), S >= ?CAND_FLOOR].

%% No candidates: mark evolved so we don't reconsider it every cadence forever.
link_by_llm([], Entry, Mem, _ReasonFun) ->
    mark_evolved(Entry, Mem);
link_by_llm(Cands, Entry, Mem, ReasonFun) ->
    apply_choice(ReasonFun(link_prompt(Entry, Cands)), Cands, Entry, Mem).

apply_choice({ok, Reply}, Cands, Entry, Mem) when is_binary(Reply) ->
    commit_links(pick(parse_choice(Reply, length(Cands)), Cands), Entry, Mem);
apply_choice(_Failed, _Cands, _Entry, Mem) ->
    Mem.

%% Set the evolved memory's links to the LLM's choice and mark it done, then give
%% each chosen neighbour a reciprocal back-link.
commit_links(Chosen, #{id := Id} = Entry, #{entries := Es} = Mem) ->
    ChosenIds = [maps:get(id, C) || C <- Chosen],
    Es1 = Es#{Id => Entry#{links => lists:usort(ChosenIds), evolved => true}},
    Es2 = lists:foldl(fun(Cid, Acc) -> add_backlink(Cid, Id, Acc) end, Es1, ChosenIds),
    Mem#{entries => Es2}.

add_backlink(Cid, Id, Es) ->
    backlink(maps:get(Cid, Es, undefined), Cid, Id, Es).

backlink(undefined, _Cid, _Id, Es) ->
    Es;
backlink(#{links := L} = C, Cid, Id, Es) ->
    Es#{Cid => C#{links => lists:usort([Id | L])}}.

mark_evolved(#{id := Id} = Entry, #{entries := Es} = Mem) ->
    Mem#{entries => Es#{Id => Entry#{evolved => true}}}.

%% Parse the LLM's reply into in-range 1-based candidate indices; "NONE" or noise
%% yields the empty set (the memory then links to nothing and is marked evolved).
parse_choice(Reply, N) ->
    Parts = re:split(Reply, <<"[^0-9]+">>, [{return, binary}]),
    Nums = [binary_to_integer(B) || B <- Parts, B =/= <<>>],
    lists:usort([I || I <- Nums, I >= 1, I =< N]).

pick(Indices, Cands) ->
    [lists:nth(I, Cands) || I <- Indices].

link_prompt(#{text := Text}, Cands) ->
    [#{role => <<"system">>,
       content => <<"You maintain an associative memory. Given a NEW memory and "
                    "numbered CANDIDATE memories, reply with the numbers of the "
                    "candidates GENUINELY related to the new memory (same topic, "
                    "entity, or causal thread), comma-separated, or the single "
                    "word NONE. Reply with numbers only.">>},
     #{role => <<"user">>,
       content => <<"NEW:\n", Text/binary, "\n\nCANDIDATES:\n", (numbered(Cands))/binary>>}].

numbered(Cands) ->
    Lines = [[integer_to_binary(I), <<". ">>, maps:get(text, C)]
             || {I, C} <- lists:zip(lists:seq(1, length(Cands)), Cands)],
    iolist_to_binary(lists:join(<<"\n">>, Lines)).

%% --- vector + lexical helpers ---

topn(Scored, N) ->
    lists:sublist(lists:sort(fun({A, _}, {B, _}) -> A >= B end, Scored), N).

cosine(A, B) when length(A) =:= length(B) ->
    safe_cos(dot(A, B), norm(A) * norm(B));
cosine(_A, _B) ->
    0.0.

safe_cos(_Dot, Denom) when Denom == 0.0 -> 0.0;
safe_cos(Dot, Denom)                    -> Dot / Denom.

dot(A, B) -> lists:sum([X * Y || {X, Y} <- lists:zip(A, B)]).

norm(A) -> math:sqrt(dot(A, A)).

id(Text) ->
    binary:encode_hex(binary:part(crypto:hash(sha256, Text), 0, 16), lowercase).

%% Lowercase, split on non-alphanumerics, drop very short words, dedup.
tokens(Text) ->
    Words = re:split(string:lowercase(Text), <<"[^a-z0-9]+">>, [{return, binary}]),
    lists:usort([W || W <- Words, byte_size(W) > 2]).

score(QTokens, ETokens) ->
    length([W || W <- QTokens, lists:member(W, ETokens)]).
