# DESIGN: Soul persistence — event-sourcing under scrutiny

**Status: PROPOSED (critical review of a shipped choice)**
**Date: 2026-07-17**

## The question

A Spartan mind's Soul is currently an **event-sourced aggregate** (`soul_aggregate`,
`evoq_aggregate`, a reckon-db stream `soul-{hash(did)}` on Ra/Khepri). We chose
this because event-sourcing is the Hecate house default. Gene Sher's original
persists the Soul as **editable files plus an append-only history log**.

This note interrogates our choice hard. The conclusion: **for the Soul,
event-sourcing is largely unjustified and actively harmful, and Gene's file model
is the better design.** The critique is scoped to the Soul; it is not a case
against reckon-db/evoq where a genuine transactional invariant exists.

## The two designs

### Gene's (Python Spartan) — and it is not naive

- **Nine editable Markdown archives**: Charter of Self, Lessons Learned, Philosophy
  of Life, Cognitive Journal, Ideas and Thoughts, What I Want, Tool Manifest,
  Knowledge Map, Knowledge Library — each with its own token window.
- `soul_session_state.json` for volatile state (working memory, grand strategy,
  scratchpad, alert countdowns).
- `_staging_buffer.json` with **crash recovery** (unflushed entries dedup'd and
  flushed before the first cognitive cycle).
- `session_raw_entry_accumulator.jsonl`: an **append-only log** of every
  observation, thought, action, and tool result — "the ground truth of how you
  think."

The critical thing: Gene **already separates editable current-state (files) from
immutable history (the append log).** He is the author of *Handbook of
Neuroevolution Through Erlang* and the creator of DXNN. He did not reach for files
out of ignorance of event-sourcing; he chose a split that gives crash-recovery, a
durable causal record, and unconstrained self-authoring at once.

### Ours (BEAM port)

- `soul_aggregate` (`evoq_aggregate`), reckon-db stream per mind.
- Events: `mind_born_v1`, `charter_amended_v1`, `lesson_recorded_v1`,
  `record_reflection_v1`, `grand_strategy_revised_v1`, working-memory revisions,
  `backend_chosen_v1`.
- `soul_state` folds the stream into `#soul{}` — **7 content fields: 3 of Gene's 9
  archives (charter, lessons, journal) plus scratch (grand_strategy,
  working_memory, backend).**
- Boot = replay the stream.

## The justifications we gave, tested one by one

**1. Atomicity — "no torn writes" (the plan's "spinoza's corruption" leak).**
A cannon for a fly. An atomic write is `write-temp + fsync + rename` (atomic on
POSIX), or any embedded DB (SQLite is ACID). One historical file-corruption
incident justifies atomic writes or SQLite, not an event-sourced distributed
consensus log. **Not a real justification for ES.**

**2. Deterministic replay reconstructs the self.**
There is no operational consumer of this property. Nobody diffs two replays to
"prove" a mind is itself. The state that gets *used* is the current fold, and Gene
obtains it in O(1) by reading files; we obtain it by replaying O(n) at every boot.
For a long-lived mind the stream only grows, so replay is a boot **cost** and a
catch-up stall (the same shape as reckon-db "replays the whole store before live
events," and our own LTM index "rebuilt from replay each boot"). **A net negative
at scale for a benefit with no consumer.**

**3. One consistent distributed store; minds migrate / HA.**
Unused. Each mind is pinned to a beam, its store on that node's `/bulk0`. Minds do
not migrate between nodes; there is no live cross-node failover. We pay for Ra/Khepri
consensus and exercise none of it. If mind mobility were ever wanted, replicating a
SQLite file or the state files is far lighter. **A benefit for a scenario that does
not exist in this deployment.**

**4. Provenance / audit / tamper-evidence.**
The provenance that matters to anyone else is the **Ed25519 signature on the mesh
fact**, not a local event stream. A local stream sits on the mind's own disk; the
operator can rewrite it; it is not tamper-evident to third parties. So local ES
yields an *ordered local log* — which Gene also has (the JSONL accumulator),
simpler and without folding. **The real provenance lives at the mesh/signature
layer; local ES provenance is redundant and weaker.**

**5. Integration facts (messages, agora) as local aggregates.**
The house doctrine itself: *domain events stay local; integration facts are
published to the mesh; never bridge.* A routed message and an agora post ARE
integration facts. Wrapping each in a one-event, no-fold local aggregate
(`message_aggregate`, `agora_aggregate`) with no reader is ceremony. The fact goes
out on the mesh, signed; the local aggregate is dead weight. **These should be
publishes, not aggregates.**

**6. Projections / realm views of the society.**
A realm dashboard is built from **published facts** (each mind emits a summary
fact; the realm subscribes), which is exactly the integration-facts pattern. It
does not require every mind to be locally event-sourced. **Realm views come from
published facts, not Soul-level ES.**

**7. Right-to-erasure.**
Retracted from all code and docs. It has nothing to do with Spartan. Worse, it is
backwards: an append-only store makes erasure *harder* (crypto-shred / tombstone),
and the reckon-db feature is not shipped. Deleting a mind, for Gene, is
`rm -rf Soul/`.

## What event-sourcing actually costs Spartan (concrete, not theoretical)

1. **It fights self-authorship — the philosophical core.** Typed events freeze the
   shape of the self into schemas *we* authored. A mind cannot invent a new archive
   or a new kind of self-record without a code change (new event + command + handler
   + projection). Spartan's entire telos is open-ended self-authorship and
   self-modification — Gene's minds rewrite their own code. Markdown lets a mind
   write and restructure anything. **ES is anti-Spartan at the level of what Spartan
   is for.** This is the decisive objection.

2. **It is breaking the live society right now.** On 2026-07-17 the running minds
   throw `wrong_expected_version` on `set_working_memory` (observed in Athena's
   logs) — optimistic-concurrency conflicts on the soul stream. A mind literally
   cannot save its working memory because of an event-sourcing version race. **This
   failure class does not exist if the Soul is a file.** We introduced a whole
   category of runtime failure in exchange for benefits that are unrealized.

3. **Boot cost.** Replay grows unbounded with a mind's life; every restart re-folds
   the entire history.

4. **Operational weight.** reckon-db / evoq / Ra / Khepri: join-races, store
   corruption, self-healing, snapshotting — all to persist a handful of fields a
   Markdown file or a SQLite row would hold. Sessions have been spent on store
   recovery adjacent to exactly this.

5. **Impedance mismatch.** The LLM authors in text. Every self-authorship act is
   translated text → command → typed event → folded state → rendered text: lossy
   ceremony around something Gene does as "write markdown, read markdown."

## Recommendation

Match the mechanism to the data, not to a house default.

- **Soul content** (the nine archives, Knowledge Map/Library): **editable text or
  SQLite rows the mind edits directly.** Extensible (the mind can add archives),
  LLM-native, O(1) boot, no write-conflicts, no per-record schema code. This is the
  biggest correction.
- **Causal history / chronicle** (turns, self-authorship acts): an **append-only
  log** (one table, or a JSONL-equivalent). Append-only is a genuine fit — but that
  is a *log*, not event-sourcing-with-aggregates: no folding, no expected-version,
  no replay-to-state.
- **Integration facts** (messages, agora, routing): **publish to the mesh**
  (signed), per the domain-events-vs-integration-facts doctrine. Drop the local
  no-fold aggregates.
- **Reserve evoq aggregates** for genuine multi-writer consistency invariants. The
  Soul has none: a mind is the single writer to its own Soul.

Net: the Soul should be **a document the mind owns and edits, with an append-only
history beside it** — Gene's exact split — running on the BEAM. Not an
event-sourced aggregate.

## Migration (there are 8 live minds on ES today)

Do not rip this out carelessly; the society is running.

1. Add a SQLite (or text) Soul store behind the existing slice API.
2. One-time export: replay each mind's stream once, write the current `#soul` to the
   new store.
3. Cut reads/writes over to the new store.
4. Keep the old stream read-only as archived history, or export it to a JSONL log.

Minds keep their identity (DID and key are unchanged) and their charter, lessons,
and journal. This also **removes the `wrong_expected_version` failures immediately.**

## Decision status

**PROPOSED.** This note argues event-sourcing is the wrong default for the Spartan
Soul. It is not an argument against reckon-db/evoq in general: where a real
transactional aggregate with a multi-writer invariant exists, event-sourcing is the
right tool. A single-writer, self-authoring, extensibility-first Soul is not that.
