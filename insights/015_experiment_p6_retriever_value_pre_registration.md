# 015 — Experiment P6: does the mind's retriever earn its keep? (pre-registration)

**Status: DRAFT, not gated, not built.** Programme S4 (external recall value).

Insight 012 named the one mechanism still standing after 011: memory that is
**external, queried at use, and freshness-aware**. The port has such a retriever.
`mind_memory:recall/3` embeds the query, takes cosine seeds, follows links one
hop, re-ranks, and falls back to lexical matching when no embedder answers.

It has never produced a number.

That is the whole justification for this experiment. We are running an embedding
model, a mesh service, a vector path and a per-eight-turn LLM call on the strength
of an untested assumption, in a programme whose entire discipline is that we do
not believe a faculty until it beats its control.

## Why this one is worth running

**Both outcomes delete code.** That is rare and it is the point.

- If semantic retrieval does not beat lexical, the embedder dependency goes: no
  ONNX model, no `io.hecate.embed` mesh call, no 8-second timeout per recall, no
  AVX2 constraint. A sovereignty and operations win, bought with a measurement.
- If LLM-evolved links add nothing over the cosine links laid at store time,
  `evolve/2` goes: one LLM call per eight turns saved, and the defect-6 machinery
  that runs it off-process becomes unnecessary.

An experiment that can only simplify the system or justify it is worth more than
one that can only add to it.

## What is under test

`mind_memory:recall/3` as it currently stands, **not a replacement.** The
hand-rolled O(n) cosine is ugly and duplicates `hecate-vector`, but it is the
measured object. Swapping it first would measure the replacement and pre-spend
infrastructure on a path this experiment may condemn.

## The frozen spec

**Task.** Paraphrase recall. A frozen probe corpus of triples
`{stored_memory, query, gold_id}`: the memory goes into the store, the query is
issued, and the retriever either surfaces the gold memory or does not.

**Metric.** `recall@2`, paired per probe. K=2 because that is production's
`?RECALL_K` after the context trim. Measuring at a K the mind does not use would
be measuring something the mind does not do.

**Arms (retrieval).**

| Arm | What it is |
|---|---|
| `lexical` | the existing fallback path, the control that matters |
| `semantic` | embed the query, cosine seeds, follow links, re-rank (the incumbent) |
| `random` | K drawn uniformly. The floor |
| `recency` | the K most recent memories, query ignored entirely |

**Arms (linking), for chain-gain.**

| Arm | What it is |
|---|---|
| `cosine_links` | links as laid at store time |
| `evolved_links` | after `evolve/2` has run its LLM linking |

Chain-gain is measured only on gold items **not** reachable as a cosine seed, so
it isolates what following a link actually buys.

## The degenerate-retriever gate

Before any arm is built, the cheapest retriever that scores well while doing
nothing useful must be written and must fail. That retriever is `recency`: it
ignores the query completely.

If `recency` matches or beats `semantic`, the probe corpus is measuring *when a
memory was stored*, not *what it is about*, and no result from it means anything.
This is why `recency` is an arm and not an afterthought, and why its failure is a
void condition rather than a footnote.

## Kill criteria (constant-free, both independent)

- **K1, the embedder earns its cost.** `semantic` beats `lexical` on paired
  probes, with the mean paired difference above sampling noise (mean > 2 × SEM).
  Not "beats by a margin": beats, above noise. A margin would be a free constant
  on a verdict, which the programme forbids. If `semantic` does not win above
  noise, it does not earn a model, a network hop and a timeout.
- **K2, evolution earns its cost.** `evolved_links` beats `cosine_links` on
  chain-gain, paired, above noise. Same structure, same reasoning.

K1 and K2 are adjudicated separately. One can die while the other lives.

## Void conditions (free constants are allowed here, and only here)

- `lexical` recall@2 ≥ 0.95 → no headroom for anything to beat. Void, not kill.
- `lexical` recall@2 not above `random` above noise → the probe corpus does not
  discriminate at all. Void.
- `recency` ≥ `semantic` → the degenerate gate fired. Void.
- Any probe where the embedder is unreachable → the semantic arm is not being
  measured. Void the run, do not silently score its lexical fallback as if it
  were semantic. **This is the failure mode most likely to produce a fake result.**
- Embed model, prefix convention or similarity metric changes mid-run → void.
- Realised query/gold lexical-overlap histogram deviates from the pre-declared
  bands → void (see the known weakness).
- Fewer than the pre-registered N scored probes → void.

## Instrument pins, recorded on every run

Borrowed straight from the M1 ledger discipline, because a retrieval number is
meaningless without them:

- embed model id and vector dimension;
- the prefix convention **actually applied**. `embedder.erl:88-90` hardcodes
  nomic's `search_query:` / `search_document:`, while the e5 family that
  `hecate-embed` ships uses `query:` / `passage:`, and the service may apply its
  own prefixes on top. A mismatch or a double prefix silently degrades the
  semantic arm, which would read as a clean K1 failure and delete the embedder
  for the wrong reason;
- the similarity metric (currently cosine over unnormalised vectors);
- `?RECALL_K`, `?LINK_MAX`, `?LINK_THRESHOLD`, `?CAND_MAX`, `?CAND_FLOOR`.

## Run prerequisites (not part of the experiment)

1. **Measure whether `io.hecate.embed` is advertised anywhere at all.** With the
   fleet decommissioned it probably is not, in which case every recall currently
   waits out an 8-second mesh timeout before falling back to HTTP. That is a live
   performance bug and it also makes the semantic arm unrunnable.
2. A frozen probe corpus, committed, with its overlap histogram measured.

## The known weakness, stated plainly

**The probe corpus decides the outcome.** Queries that share surface tokens with
their gold memory favour `lexical`; queries that share none favour `semantic`.
Whoever writes the probes picks the winner, and I would be writing them.

My proposed mitigation: stratify probes by measured Jaccard overlap into
pre-declared bands with pre-declared counts, report per band as well as overall,
and void if the realised histogram deviates from what was declared before any
probe was authored.

I do not think that fully closes it. Band membership is measurable, but *within* a
band I still choose the wording. This is the weakest part of the design and it
should be the first thing the gate attacks.

## The signed sentences, written now

**If K1 passes:** "On paraphrase recall over a frozen probe corpus, semantic
retrieval beats lexical above sampling noise. The embedder earns its cost. Scope:
recall@2 on authored paraphrase probes at small store sizes, not a mind's live
recall over its own history."

**If K1 fails:** "Semantic retrieval does not beat lexical above sampling noise on
this corpus. The embedder dependency, the ONNX model and the mesh call are
deleted; recall falls back to lexical. Scope: this kills the embedder *as
configured and at this store size*, not the idea of semantic retrieval."

**If K2 passes:** "LLM-evolved links reach gold memories that cosine links do not,
above noise. Gene's agentic linking earns its call."

**If K2 fails:** "Evolved links add nothing over cosine links. `evolve/2` is
deleted."

## Odds

Honestly: K1 near even, perhaps slightly favouring semantic. At K=2 over a small
store, lexical matching on paraphrases is a stronger baseline than intuition
suggests, and 011's whole lesson was that cheap lookup beats machinery more often
than we expect. K2 I would put at maybe 30% survival: one LLM call per eight turns
choosing links by index is a thin intervention.

## ELI5

The mind keeps a diary and, when something happens, tries to find the old diary
entry that relates to it. There are two ways it can look: by *meaning* (which
needs a language model to turn text into numbers, and that model costs money,
memory and a network call), or by *matching words* (which is free).

Nobody has ever checked whether the expensive way actually finds better entries
than the free way. This experiment writes down, in advance, exactly what "better"
means and how much better it has to be. Then we test it.

The nice part is that we win either way. If the expensive way is better, we now
know it and can say so. If it is not, we delete a whole pile of machinery and the
mind gets simpler, cheaper and easier to run.

The risky part is the test set. If we write the practice questions using the same
words as the diary entries, word-matching wins automatically. If we carefully
avoid every shared word, meaning-matching wins automatically. So the person
writing the questions can accidentally decide the answer before the test is run.
That problem is not solved yet, and it is written down here so it cannot be
quietly forgotten.
