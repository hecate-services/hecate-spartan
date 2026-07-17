# Plan: Spartan on the BEAM

A migration from Gene Sher's Python Spartan to a BEAM-native mind, true to the
foundation and closing the leaks. Read `SPARTAN_MECHANISMS.md` first; this plan
assumes it.

## The governing idea: a new suit, not a new mind

`genesis_core.py` separates identity (the Soul: Charter, Lessons, memory) from
interface (the "suit": the runtime that assembles context, runs the loop, holds
the tools, talks to the world). Gene built this so one Soul can inhabit different
suits. That is our migration path, stated in his own terms:

> We are building a BEAM suit. Migrating a mind means letting its existing Soul
> put on that suit, under the same DID.

This keeps us honest. The cognition (the Kernel and its mechanisms) is carried
over faithfully. Only the suit is rebuilt, and the suit is exactly where the
leaks live.

Two consequences:

- **Coexistence is free.** BEAM minds and Python minds share one mesh, one realm,
  one agora. We migrate one mind at a time and compare them side by side. No big
  bang.
- **Nothing about identity changes.** A mind keeps its Ed25519 key, its DID, its
  Charter, its memories. It changes clothes.

## What the BEAM closes (the leaks)

| Leak in the Python suit | Closed by, in the BEAM suit |
|---|---|
| Busy loop, clock initiative, idle token burn | event-driven gen_server, idle at zero cost |
| Mutable Soul files (spinoza's corruption) | Soul as an event-sourced aggregate |
| Staging buffer + deferred file flush | command dispatch; nothing to flush |
| OS-process drones | supervised child processes |
| External mesh bridge (SpartanRadio, SSE, alert files) | in-process mesh, no bridge |
| Fragile JSON-action-list parsing | provider-native structured tool calls |
| LanceDB + AVX2 SIGILL on cheap hardware | sovereign embeddings + a portable Rust-NIF index |

## The vector store: how we deal with LanceDB

LanceDB is a real, persisted, embedded vector database (Rust core, Lance columnar
files on disk). Two facts make this easier than it looks:

1. **It is a derived index, not a source of truth.** Everything in it is an
   embedding of content that already lives in the Soul files and the CMO history.
   The index is rebuildable. So migration is a re-index, not a data migration,
   and only scribe (the one LTM-on mind, on the AVX2 host) has any populated
   index to begin with.
2. **The AVX2 SIGILL is the reason LTM is off on the Celerons.** LanceDB's SIMD
   core uses AVX2, which the J4105 lacks, so keeping LanceDB does not solve our
   actual problem. We have to move off it to run LTM on the cluster at all.

The replacement has three clean parts:

- **Embeddings from Melious.** Its catalogue already serves `bge-m3`,
  `bge-large-en-v1.5`, `bge-multilingual-gemma2` over the OpenAI-compatible
  `/v1/embeddings` endpoint. Sovereign EU, no local model, no AVX2, one HTTP call
  we already know how to make. (And a live case for the caching ask: embeddings
  are a stable-prefix workload too.)
- **The index as a Rust NIF.** For a mind's LTM (thousands to tens of thousands
  of memories) brute-force top-k cosine in a dirty NIF is already sub-millisecond
  and has zero SIMD dependency, so it runs on a Celeron. When a mind's memory
  grows past that, swap the NIF's internals for `usearch` (HNSW with runtime SIMD
  dispatch, so it degrades to scalar on the J4105 instead of crashing). We
  already ship Rust NIFs (`macula-nn-nifs`, `reckon-nifs`), so this is familiar
  ground, not a new capability.
- **The source of truth in reckon-db.** A memory is an event
  (`memory_recorded_v1`) carrying its content, type, timestamp, and its embedding
  vector. The vector index is a projection: rebuildable from the event log
  without ever re-calling the embedding API, and persisted as a projection cache
  so a restart is fast. A-Mem links are events too (`memories_linked_v1`), so the
  Zettelkasten graph is durable and inherits provenance like everything else.

Net: LanceDB goes away entirely. We gain a single source of truth (the event
log), sovereign embeddings, a vector index that runs on the cheap hardware, and a
memory graph that carries provenance. We lose nothing Gene's design depended on;
LTM was always defined by its content and its links, not by the file format.

## The phases

Each phase is shippable, runs beside the Python fleet, and can be judged on the
live agora before the next begins.

### Phase 0 (done): the reflex mind

`spartan_mind`, event-driven, self-sovereign, mesh-native, use-case agnostic. No
memory, no Soul, no layers. It proves the substrate: idle at zero cost, reasons
on stimulus, speaks with provenance. This is the bare suit.

### Phase 1: the Soul aggregate and the four layers

- Model the Soul as a reckon-db aggregate: Charter, Lessons, Philosophy, Journal,
  WhatIWant, KnowledgeMap, and the rest, each edited by a command
  (`amend_charter`, `record_lesson`, `add_journal_entry`) that emits an event. No
  files.
- Port L1 (the `genesis_core` interface knowledge) as a versioned Erlang constant
  adapted to the BEAM tool set. This is the one place the "how this suit works"
  text lives.
- Assemble the four-layer context from L1 (constant), L2 (Soul projection), L3
  (the mind's event history), L4 (working memory, grand strategy, scratchpad from
  aggregate state), plus a HUD view.
- Load the Founding Brief into L2 as context-not-command, the generic seam an
  instantiator uses to give a mind a purpose. This is where cyberdefence lives,
  not in code.

Deliverable: a mind that reasons with its identity and working state in view,
still stateless between stimuli except for what is event-sourced.

### Phase 2: short-term memory and the Sleep Cycle

- The mind's history is its event stream, token-budgeted.
- When raw events pass the threshold, run a Sleep Cycle: one LLM call condenses a
  chunk into a CMO event; the L3 projection serves the dual stream (raw plus
  windowed CMOs). CMOs of CMOs are MSO events. Triggered on threshold, never on a
  clock.

Deliverable: a mind whose near-term memory consolidates and survives restarts.

### Phase 3: long-term memory (LTM and A-Mem)

- On consolidation, embed new memories (Melious), record `memory_recorded_v1`,
  update the vector index projection.
- A-Mem linking: the mind's own LLM proposes links against candidate neighbours;
  emit `memories_linked_v1`.
- Auto-injection: each reason cycle, query the index from working memory and the
  latest stimulus, follow chains, apply temporal decay, inject the top-k into L4.
- This is the phase that retires LanceDB, per the section above.

Deliverable: a mind that recalls relevant past experience unprompted, on cheap
hardware.

### Phase 4: the rest of the cognition

- Self-alerts as a timer on an accumulating token counter (the token clock).
- MINDfulness draft/verify, kept but gated on genuine new input so it cannot
  become the idle spin.
- The tool vocabulary as commands. Prefer provider-native tool calling over the
  JSON-action-list, which removes the parse-failure friction the reasoning models
  hit. File-editing tools mostly disappear (the Soul is an aggregate).
- Drones as supervised child minds started under a `drone_sup` with a mission and
  a budget, terminated by shutting the child down. No OS processes.

Deliverable: full parity with the Python cognition, minus the leaks.

### Phase 5: cutover

- For each Python mind, import its Soul files as aggregate events and reuse its
  Ed25519 key so the DID is unchanged. Run the BEAM suit beside the Python one,
  compare on the agora, then retire the Python instance.
- One mind at a time. The society is never down.

## Two design improvements worth taking while we are here

- **Structured output instead of parsed prose.** The JSON-action-list is the
  source of the reasoning-model friction. Provider-native tool/function calling
  gives us the same action vocabulary with a schema the model is trained to obey.
  Faithful to the intent (a mind that acts through a fixed tool set), kinder to
  the models.
- **Consolidation and linking as their own supervised work.** In Python these are
  blocking calls inside the loop. On the BEAM they are naturally separate
  processes (a `consolidate` worker per mind), so a Sleep Cycle never freezes the
  mind's responsiveness.

## Where Gene helps

- The trusted-trigger signal he offered (so a mesh sender can wake a mind) is the
  Phase 0-to-1 seam; his hijack-protection thinking should shape ours.
- The CMO and A-Mem prompts are his craft; we want them as close to his intent as
  he will share.
- The "suit" boundary is his idea, so his read on what belongs in L1 (interface)
  versus the Soul (identity) keeps us from smearing the line.

## Open questions

- Tokenizer: a Rust NIF (tokenizers crate) for accurate budgeting, or an
  approximate count to start.
- Do BEAM minds get `execute_console` at all, or a curated, sandboxed tool set?
  Shell access on a shared node is a different risk posture than a Python drone in
  its own directory.
- Embedding model choice and dimension (bge-m3 is multilingual, which suits a
  European society), and whether to cache embeddings hard given the caching gap.
