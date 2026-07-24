# 015 — Experiment P6: does the mind's retriever earn its keep? (pre-registration)

**Status: REDESIGNED after a DESIGN gate that rejected draft 1. Now BLOCKED ON
DATA, and deliberately not built.** Programme S4 (external recall value).

Insight 012 named the one mechanism still standing after 011: memory that is
**external, queried at use, and freshness-aware**. The port has such a retriever,
and it has never produced a number. That is the whole justification.

This note records the design, the four things the gate changed, and the reason the
experiment cannot honestly be run yet.

## What the gate found, and what it cost

**Blocking: chain-following is a no-op.** `mind_memory.erl:127-147`. `Seeds` is the
global top-K by cosine over all vectored entries; `Expanded` is a superset of
`Seeds` and a subset of the same population; therefore the top-K of `Expanded` is
necessarily `Seeds` again. For every query, every link set, every K.
`follow_chains/2` cannot change what `recall/3` returns.

Draft 1 had a second kill criterion (K2) measuring chain-gain on gold items *not*
reachable as a cosine seed. Those are exactly the items the re-rank discards. **K2
was guaranteed to fail at any N**, and would have read as a clean signed negative
about Gene's agentic linking rather than what it is: a code defect wearing an
experiment's clothes. This is the "never sign a faculty verdict on a silent
faculty" rule from arena rounds 8 and 10, caught one gate earlier this time.

K2 is removed. The no-op is recorded as a defect and re-registered only against a
repaired retriever. A free consequence, no experiment required: **`evolve/2` has no
effect on the system**, so its LLM call every eight turns is pure cost.

**"Constant-free" was rhetoric.** Draft 1 claimed K1 was constant-free because it
used `2 × SEM` rather than a margin. That is 1.96 rounded, which is α = 0.05 in a
noise-shaped costume. The programme's real distinction is not constants versus no
constants, it is **declared before data versus tuned after**. A pre-declared
significance level is legitimate; claiming it is not a constant is not. Corrected
throughout.

The test was also wrong. Paired recall@2 differences live in {−1, 0, +1}, where the
normal approximation behind SEM is shaky at plausible N and the pairing is wasted.
**McNemar / exact sign test on discordant pairs**, α declared up front along with
whether it is per-test or family-wise.

**The lexical control was a strawman, biased in the expensive direction.**
`mind_memory.erl:277-281` scores raw intersection over `usort`ed tokens: no IDF, no
term frequency, no length normalisation, no stemming, and a `byte_size > 2` filter
that keeps "the" and "and". Beating that is not evidence that embeddings beat
lexical retrieval. And the bias runs the costly way: **a weak control makes the
embedder easier to keep**, so the strawman defends an ONNX model and a mesh
dependency. Two lexical arms now, and the delete decision hangs on the strong one.

## The frozen spec (as redesigned)

**Task.** Paraphrase recall over a frozen corpus of `{stored_memory, query,
gold_id}`.

**Metric.** recall@2, paired. K=2 because that is production's `?RECALL_K`.

**Arms.**

| Arm | What it is |
|---|---|
| `semantic` | embed the query, cosine top-K (with chains inert, this is exactly the embedder under test) |
| `lexical_incumbent` | the fallback as shipped. Answers "does semantic beat what we actually degrade to?" |
| `lexical_bm25` | BM25, or at minimum IDF-weighted and length-normalised. Answers "does the embedder beat lexical retrieval done competently?" |
| `recency` | the K most recent memories, query ignored |
| `random` | uniform draw, with a declared number of restarts and its own interval reported |

**K1, the only kill criterion.** `semantic` beats **`lexical_bm25`** on paired
probes by an exact sign test at a pre-declared α. Beating `lexical_incumbent` is
reported but does not decide: if semantic loses to BM25, the right action is to
delete the embedder **and** upgrade the fallback, a double win draft 1 could not
see.

**The degenerate-retriever gate.** `recency` ignores the query entirely. If it
matches or beats `semantic`, the corpus is measuring *when* something was stored
rather than what it is about, and the run voids.

## Void conditions (pre-declared constants belong here, and only here)

- `lexical_bm25` recall@2 ≥ 0.95 → no headroom. Void, not kill.
- `lexical_bm25` not above `random` → the corpus does not discriminate. Void.
- `recency` ≥ `semantic` → the degenerate gate fired. Void.
- **Any probe whose gold entry has `vec => undefined`.** `remember/2` embeds at
  store time and stores `undefined` on failure; `vectored/1` then filters that
  entry out of the semantic arm *permanently*. A gold memory stored during an
  embedder blip is invisible to semantic forever and scores as a clean miss.
  Assert every gold entry is vectored before scoring.
- **Any probe where the query embedding fails**, because `retrieve/4` falls back
  to `lexical` silently. Scoring that as the semantic arm is the single most
  likely way this design produces a confident wrong answer.
- Store size or distractor composition deviating from the declared value. recall@2
  is dominated by how many memories the store holds: ten makes every arm look
  brilliant, ten thousand makes all of them look poor.
- Model, dimension or convention changing mid-run.
- Tie-break rule unstated or differing between arms (`topn/2` sorts over map-value
  order; at K=2 with integer lexical scores, ties are common).
- Fewer than the pre-registered N scored probes.

## Pins (established, not assumed)

Transport is the **mesh**. `hecate-embedder` is the mesh embedding service and
consumers reach it with `macula:call(io.hecate.embed, #{text, kind})`. Raw HTTP is
not a consumer transport here.

Read off the running deployment rather than inferred:

- backend `nif`: fastembed in-process, model baked into the image
  (`hecate-embedder` `sys.config`);
- **vector dimension 384**, confirmed by calling the handler on its own node;
- the `kind` → prefix convention is applied **service-side**, so the client
  hardcodes nothing;
- similarity: cosine over unnormalised vectors (`mind_memory:cosine/2`).

**The HTTP fallback stays** (operator decision): a mind should not lose semantic
recall because the mesh hiccuped. So the experiment handles it by **voiding**, not
by amputation. Any probe whose embedding was not served by the pinned mesh path
voids the run.

Keeping it surfaced a real production bug, now fixed (defect 10). `prefer_mesh/3`
falls back **per call**, so one store can hold vectors from two models of two
widths, and `cosine/2` answers `0.0` on a width mismatch. A mismatched query
therefore scored *every* memory `0.0`, and `topn/2` returned an arbitrary K as
though they were the nearest: the mind told its most relevant memories are
whichever ones sorted first, silently, exactly when the fallback was doing its
job. `mind_memory:comparable/2` now filters recall to same-width vectors, so a
query from a different model finds nothing comparable and degrades to lexical,
which is a real answer.

## Why this is blocked on data

Draft 1 proposed authoring the probes and stratifying them by measured Jaccard
overlap. The gate rejected that, and it is right: bands constrain overlap, not
wording. Within a fixed band the author still chooses synonym rarity,
morphological distance, word order, and whether the shared tokens carry
information. **And the band weights are also the author's**, while the verdict is a
single decision taken at some mixture. Authored probes would measure my prose
habits.

The honest alternative is to **stop authoring**: harvest real stored memories from
lived operation, generate queries by a pre-declared seeded mechanical
transformation, and take the band weights from the production overlap
distribution rather than from a preference.

That requires lived data. **None survived.** The 2026-07-19 decommission wiped
`/bulk0/hecate/spartan/*` on every beam, including A-Mem stores and souls, and
nothing remains locally.

**So P6 is blocked on data, and saying so is the result.** Authoring a corpus to
get a number anyway would produce a measurement of the author, dressed as a
measurement of the retriever.

### The unblock path

The instrument that produces the corpus already exists: the append-only journal
built for defects 2, 3 and 7 records `experience_observed_v1` and
`stimulus_declined_v1` with their text. A mind running with it on generates
exactly the lived `{stimulus, memory}` pairs this experiment needs, and the
realised overlap distribution comes out of the same record.

So the prerequisite is: **run a mind long enough to accumulate a corpus.** That
needs a pinned, un-rate-limited endpoint, which is the same prerequisite M1 has
been waiting on. Both open experiments now converge on one blocker, which is worth
knowing.

## The signed sentences, written now

**If K1 passes:** "On paraphrase recall over a harvested corpus, semantic
retrieval beats a competent BM25 baseline at the declared α. The embedder earns
its cost. Scope: recall@2 at the store sizes observed in the harvest, not a
general claim about embeddings."

**If K1 fails:** "Semantic retrieval does not beat a competent lexical baseline.
The embedder dependency, the ONNX model and the mesh call are deleted, and the
fallback is upgraded to the baseline that beat it. Scope: this kills the embedder
as configured at this store size, not the idea of semantic retrieval."

## ELI5

The mind keeps a diary. When something happens, it looks for the old entry that
relates. It can look by *meaning*, which needs a model that costs memory and a
network call, or by *matching words*, which is free. Nobody ever checked whether
the expensive way finds better entries.

Two things went wrong with the first version of this test, and both are worth
knowing about.

The first: the "follow the links between related entries" feature does nothing at
all. Not "does little" — provably nothing, for mathematical reasons. The test was
about to measure that feature and would have reported "linking doesn't help",
which sounds like a discovery about the idea and is actually a bug in our code.

The second: the free word-matching method we were comparing against was a
deliberately poor version of word-matching. Beating a weak opponent would have let
us keep the expensive machinery on flattering evidence.

And the test can't run yet anyway. To be fair, the practice questions have to come
from things a mind actually did, not from someone writing questions by hand,
because whoever writes them decides who wins. Those records were deleted when the
system was taken down. So the honest answer is "we cannot run this yet, and here
is exactly what has to exist first", rather than running it and getting a number
that means nothing.
