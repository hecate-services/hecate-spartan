# PLAN — Mind instrument repair

**Status:** Draft 3, DESIGN-gated, reconciled with `DESIGN_SOUL_PERSISTENCE.md`
**Owner:** Raf
**Companion:** [`PLAN_HECATE_SPARTAN.md`](PLAN_HECATE_SPARTAN.md) (stale, Appendix B),
[`../docs/PLAN_RIP_ES.md`](../docs/PLAN_RIP_ES.md),
[`../insights/README.md`](../insights/README.md)

Eight defects in `inhabit_mind`: seven found by two independent code studies, an
eighth found while reviewing this plan's own failure model. It fixes them, and
orders the work so that **nothing precedes the programme's one cleared
experiment**.

---

## 1. Where the defects come from

They are not seven independent bugs, and they are **not** a silent regression.

On 2026-07-17, event sourcing was removed from this repo deliberately, in five
atomic always-green commits ([`docs/PLAN_RIP_ES.md`](../docs/PLAN_RIP_ES.md)),
against a reasoned critique
([`docs/DESIGN_SOUL_PERSISTENCE.md`](../docs/DESIGN_SOUL_PERSISTENCE.md)).

The decisive objection in that critique is not operational, it is about what
Spartan is for:

> **It fights self-authorship, the philosophical core.** Typed events freeze the
> shape of the self into schemas *we* authored. A mind cannot invent a new archive
> or a new kind of self-record without a code change. Markdown lets a mind write
> and restructure anything. **ES is anti-Spartan at the level of what Spartan is
> for.**

That is right, and it is why the Soul is thirteen readable Markdown archives
(`soul.erl:25-39`: `CharterOfSelf.md`, `LessonsLearned.md`, `PhilosophyOfLife.md`,
`CognitiveJournal.md`, and the rest). It is also why the operational objections
followed: `wrong_expected_version` on `set_working_memory` was breaking live minds,
and every self-authorship act was being laundered through text → command → typed
event → fold → text for something Gene does as "write markdown, read markdown".

**But the same document recommended a split, and only half of it shipped.**
`DESIGN_SOUL_PERSISTENCE.md:139-142`:

> **Causal history / chronicle** (turns, self-authorship acts): an **append-only
> log**. Append-only is a genuine fit, but that is a *log*, not
> event-sourcing-with-aggregates: no folding, no expected-version, no
> replay-to-state.

Gene has both halves: editable Markdown archives **and**
`session_raw_entry_accumulator.jsonl`, "an append-only log of every observation,
thought, action and tool result, the ground truth of how you think". The port kept
the documents and dropped the accumulator.

**The seven defects are the missing half.** Every durable thing a mind owns is now
a file rewritten in place, with no record beside it:

| Evidence | Consequence |
|---|---|
| `memory_store:trim/2` rewrites the tier file with fewer entries | Defect 2: consolidation can destroy the record |
| No cheap place to record an unreasoned event | Defect 3: skipped stimuli vanish |
| `soul_area.erl:73`, `soul.erl:184` write files with no history | Defect 7: one bad self-edit is unrecoverable |
| No per-call record anywhere | Defect 4: insight 014 has nowhere to put a cost ledger |

So the substrate work in this plan is not a reversal of PLAN_RIP_ES. It is the
part of that plan that was left unpriced.

Defects 1 (charter render), 5 (injection holes) and 6 (blocking `evolve`) are
ordinary bugs, unrelated to any of this, fixable in parallel.

---

## 2. Design decisions

### D1 — A per-mind append-only journal. Not evoq.

This is not a new proposal. It is the unbuilt half of
`DESIGN_SOUL_PERSISTENCE.md`'s own recommendation, and Gene's own split.

**Rejected: re-adopting reckon_db/evoq.** It would reverse a one-week-old
executed decision whose central objection (typed schemas cap self-authorship)
still stands, and it would put the open `hecate_om` boot-ordering bug on the
critical path of a defect repair. A repair plan whose prerequisite is fixing a
platform bug in another repo is a platform project wearing a repair plan's
clothes.

**Adopted: one append-only journal per mind.** A single file of appended records,
written at the end and never rewritten, fsynced. No folding, no expected-version,
no replay-to-state — the three things that made the Soul aggregate hostile.

**The document stays the record. The journal sits beside it.** This is the
distinction that keeps the Markdown property intact:

| Data | Mechanism | Why |
|---|---|---|
| Soul archives (13 `.md`) | documents the mind edits directly | authored prose, human-readable, hand-editable, extensible without a code change |
| CMO / MSO gists | **should also be Markdown** (today they are opaque `.mem` terms, `memory.erl:27-29`) | authored prose. A mind's condensed autobiography should be readable |
| STM raw turns, stimuli, inference metering | **append-only journal** | observations, not authorship. High volume, never read by hand, needs audit |
| Integration facts (messages, agora) | mesh publishes, signed | already correct, unchanged |
| evoq aggregates | none in this repo | see D1.2 |

STM becomes a **window over the journal**, so `trim` is a cache operation and
cannot delete history. The Soul's `.md` files stay authoritative and are never
regenerated from the journal; the journal records the *act* (and, because the
self-authorship tools already carry full replacement text, that is enough to
recover a prior version for audit without making the file a derived artifact).

This buys the entire structural guarantee that matters: **destructive loss is not
a bug you fix, it is a state you cannot express**, because nothing writes anywhere
but the end. Roughly 150-200 lines, zero new dependencies, zero cross-repo risk.

It also preserves every property PLAN_RIP_ES was protecting:

| PLAN_RIP_ES property | Preserved? |
|---|---|
| Store-free (no reckon-db, no evoq) | Yes |
| Mesh-native | Yes, untouched |
| Single writer per mind | Yes |
| `wrong_expected_version` impossible | Yes — append-only, no expected-version check |
| Per-faculty self-healing | Yes — caches rebuild from the journal |

What evoq would additionally buy (command validation, multi-consumer
projections, versioned replay tooling) is not needed here: every mind is
single-writer by construction, and there are no second consumers of mind events.

**Journal vocabulary.** These are *observations of what happened*, never
mechanisms for how memory should work:

| Record | Written when | Carries |
|---|---|---|
| `stimulus_received_v1` | any external signal reaches the mind, reasoned or not | sanitized text, source, topic |
| `stimulus_declined_v1` | the engagement gate skips it | reason: `busy` / `cooldown` / `own_speech` |
| `turn_taken_v1` | the mind reasons | heard, thought, tool calls |
| `inference_metered_v1` | every LLM attempt, including failures and retries | see below |
| `gist_formed_v1` | a CMO or MSO is successfully reflected | tier, **the gist text**, covered span |
| `charter_amended_v1` and the other self-authorship records | a self-authorship tool fires | as today's tool args |

`gist_formed_v1` must carry the gist text: it is LLM output and is not
reproducible by replay.

**Deliberately excluded: `memory_superseded_v1`.** Supersession is the mechanism
that experiment P7 exists to test, and P7's kill criterion is precisely "if
supersedes-links do not cut stale-surfacing, do not add the knob". Baking it into
the substrate before the measurement is the fix preceding the test.

#### D1.1 — `inference_metered_v1` is the cost ledger

```
provider, model, model_version, prompt_hash,
prompt_tokens, completion_tokens, cached_tokens, total_tokens,
latency_ms, attempt, outcome
```

Exactly what insight 014 requires, plus what the assay protocol requires (the
transcript is the record, because the run is not re-derivable). One record closes
defect 4, unblocks M1, fixes the `self_alerts` token-clock stall (usage absent
currently parses to 0), and produces the `cached_tokens` evidence already being
raised with the inference provider.

**Justification discipline:** the journal is justified on loss-safety and
auditability, which are mechanical claims. It is **not** claimed to improve the
mind's continuity or identity. That claim would be unfalsifiable and is out.

#### D1.2 — When event sourcing *would* earn its place here

`DESIGN_SOUL_PERSISTENCE.md:146,168-171` already states the criterion, and it is
not an argument against evoq in general:

> **Reserve evoq aggregates for genuine multi-writer consistency invariants.**
> Where a real transactional aggregate with a multi-writer invariant exists,
> event-sourcing is the right tool. A single-writer, self-authoring,
> extensibility-first Soul is not that.

Applied to this repo today, honestly: **nothing meets the criterion.** Not because
event sourcing is wrong, but because every candidate is single-writer.

| Candidate | Writers | Verdict |
|---|---|---|
| Soul | the mind alone | single writer, and typed schemas cap self-authorship |
| Memory tiers, LTM | the mind alone | single writer |
| Cost ledger | the mind alone, append-only | a log, not an aggregate |
| Registry, inbox, agora | many peers, but ordering and provenance come from signed mesh facts | publishes, per the integration-facts doctrine |

What *would* change the answer is a capability where two writers contend on one
invariant. Concrete candidates if they are ever built: a shared inference budget
several minds on a node draw down (double-spend matters), or the committee
redesign as membership-by-delegation with a quorum gate (concurrent joins against
a quorum is a real invariant). Neither exists. Revisit the question when one does,
against this criterion, not against a house default.

#### D1.3 — The failure model, and what the journal is not

The document and the journal are **not two copies of one thing**. The document is
state; the journal is a record of acts. Divergence needs reconciling only when one
is derived from the other, and neither is. That is the same property that makes
evoq unnecessary here.

**The document always wins. Unconditionally.** No exceptions, no "unless the
journal is newer".

A torn file is already impossible for Soul areas (`soul_area.erl:71-74` writes
tmp-then-rename). The only crash disagreement is a torn *pair*:

| Crash window | Result |
|---|---|
| Document landed, journal entry lost | content exists, the act is unrecorded. **Lossy** |
| Journal entry landed, document write lost | an act recorded that the document does not show. **Not lossy**, provided the entry carries the content |

**Ordering rule:** append to the journal first, carrying the **full intended
prose**, fsync, then write the document. This removes the lossy direction and
leaves only journal-ahead-by-one, which destroys nothing.

**Two anti-requirements.** Named here so nobody adds them later as a small
improvement:

1. **Never auto-apply a journal-ahead entry to the document at boot.** That is the
   reconciliation problem reintroduced in one line.
2. **Never build a drift detector that diffs the document against the journal.**
   It is undecidable by construction: a legitimate hand-edit made outside the mind
   (which must survive) and a crash-window gap are indistinguishable. Any such
   detector either reverts real edits or cries wolf. A boot-time notice may key
   off a did-my-last-write-complete marker only, and its response is a log line,
   never a write.

**What the journal therefore is not.** It is incomplete by design, because
hand-edits bypass it, and it may be ahead by one act after a crash. It is an
archive of what the mind *did*, not a history of what the file *contains*.
Recovery from it is **manual and assisted, never automatic**. Saying "audit and
recovery" without that qualifier oversells it.

**Two classes, and loss-safety comes from different places in each:**

| Class | Members | Authority | Loss-safety from |
|---|---|---|---|
| Authored documents | Soul areas, and CMO/MSO gists under defect 2b | the file | atomic rename plus journal-first ordering carrying the prose |
| Derived / ephemeral | STM windows, trim victims, recall caches | the journal | rebuilt from the journal; this is where "structurally impossible to lose" is a literal claim, and where the trim-without-archive defect lives |

Defect 2b moves the gists from the second class into the first. That is
deliberate, but it means their loss-safety comes from the journal carrying the
prose, not from replay.

**Durability note:** none of these paths currently `fsync`. `rename` is atomic
with respect to readers but not durable across power loss. The journal append is
the one place worth paying for an fsync.

### D2 — Vector path: deferred, gated on P6

**The apparent conflict between org rules is false.** Insight 012's "external"
means external to the **engine**, not external to the process: 011's kill
mechanism is history mutating the working machinery, and a queried in-process
store mutates nothing. `mind_memory` already satisfies 012. The commons that 012
points at is the *shared* corpus, which is hecate-rag's job. A mind's *private*
long-term memory over mesh RPC would add a network dependency to every recall and
couple experiment reproducibility to a running service, which is hostile to P6
and P7. So: in-process for private LTM, hecate-rag for the commons.
`prefer_architectural_correctness` and 012 agree once the two stores are
distinguished.

**But the decision is not taken now.** P6's pre-registered kill can delete the
semantic path outright. Swapping `mind_memory`'s hand-rolled cosine for
`hecate_vector` before that number exists would change the measured object and
pre-spend infrastructure on a possibly-condemned path. Run P6 against the
incumbent; O(n) cosine at probe-corpus scale is not a validity threat.

### D3 — Instrumentation, applied strictly

Instrumentation is *anything whose absence makes a registered measurement wrong
or impossible*. Applied strictly to the measurements that actually exist:

- M1 is a standalone extraction eval. It touches no Soul and no stimulus path.
- P6 and P7 use constructed probe corpora, not lived turns.
- There is no registered live-mind measurement; the society is decommissioned.

**Therefore instrumentation is: the ledger fields, the M1 checker/corpus/runner
per frozen 014, and the P6/P7 probe instruments. Nothing else.** Charter render
and dropped stimuli are repairs, not instrumentation — an earlier draft of this
plan put them in the instrumentation phase and failed its own rule.

**Forward-declared dependency:** if a future experiment measures lived recall over
a mind's own history, defect 3 (dropped stimuli) becomes instrumentation for it,
because the chronicle would be a biased sample. Declare that when such an
experiment is registered, not before.

---

## 3. Ordering

Nothing precedes M1. It is the programme's only cleared experiment.

| Step | Work | Gates what |
|---|---|---|
| **1** | Ledger fields (defect 4) + M1 build per frozen 014 → **run M1** | nothing may precede; the spec is not touched |
| **2** | Journal + never-trim-without-archive (defects 2, 3, 7) | pure repair, deterministic tests, corrupts no experiment |
| **3** | P6 probe instrument → run against the **incumbent** retriever | D2 |
| **4** | D2 decision, gated on P6 (pass → `hecate_vector` in-process; fail → delete the semantic path and the decision dissolves) | |
| **5** | P7 staleness → only then any supersession mechanism, and only on a P7 pass | |
| **∥** | Defects 1, 5, 6 in parallel with 3-5 | they gate nothing |

Wrong-measurement traps avoided by this order: D2 before P6 would measure the
replacement rather than the incumbent; `memory_superseded_v1` before P7 is the fix
preceding the test; any `hecate_om` work bundled ahead of M1 puts unbounded
platform work on the critical path.

---

## 4. Work packages

### Step 1 — Ledger and M1

**Defect 4 — DONE.** Scoped strictly to what insight 014 names as ledger
requirements, nothing more.

M1 does not use the production carousel: `self_audit_extract:call/2` is its own
pinned temperature-0 client. So the ledger work landed there, and separately in
the production client for the token clock.

**The harness has since moved out of this repo** to
[`hecate-spartan-programmes`](https://codeberg.org/hecate-services/hecate-spartan-programmes),
along with its tests and the frozen corpus. It had been living in
`apps/hecate_spartan/src/weigh_self_audit/`, and the release is
`[hecate_spartan, sasl]`, so the experiment shipped inside the service. That is
faber's insight 047 (a runner living inside its subject drifts with it, and a
buggy runner yields a feed that is wrong and internally consistent). The
programmes repo deliberately does **not** pin hecate-spartan: for M1 the subject
is a prompt protocol rather than service code, and pinning would drag macula,
reckon-db and their NIFs into a harness that needs a URL and a model name.

| 014 requirement | Was | Now |
|---|---|---|
| prompt + completion tokens | captured | captured, and `total` falls back to the parts when a provider omits the sum |
| **wall-clock per item** | absent | `elapsed_ms`, spanning the whole call including every retry and backoff sleep |
| **retries counted** (void condition) | absent, and the module's own doc comment falsely claimed a retry raised the call count | `retries`, threaded through the key-rotation loop |
| **model/stack change mid-run → void** | could not fire; no row carried the model | `model` on every row; `self_audit_assay:model_stable/1` across calibration and confirmatory slices, folded into `void` and `pass` |

Added beyond 014, deliberately: `cached` tokens, parsed from both the OpenAI
nested shape and the top-level shape brokers use. **Observational only.** No kill
or void criterion reads it, so it cannot move the verdict. It is recorded because
a repeated stable prefix is most of an agent's cost, and this is the number that
evidences it.

Deferred to step 2, correctly: `prompt_hash` and `outcome` were in this plan's
`inference_metered_v1` sketch but are not named by 014, and there is no journal to
write records to yet.

*Verified:* 199 eunit green, elvis clean, no new dialyzer warnings (the two in
`self_audit_extract` are pre-existing dead clauses, present at HEAD). Measured
delta on the token clock: a provider reporting parts but no total previously
yielded **0**, now yields **1000**, so scheduled self-alerts no longer freeze.

**Still blocked, and not by code:** running M1 needs a pinned un-rate-limited
endpoint and the real frozen corpus. Both are RUN prerequisites, unchanged. When
it runs, use insight 014 exactly as frozen. The evidence-only-verify idea is a
**separate** pre-registration (M2), never an edit to a cleared spec.

### Step 2 — Journal — DONE

`mind_journal` is one append-only file per mind: length-framed records written at
the end, fsynced, never rewritten. Appends are **synchronous on purpose**, because
the ordering rule is only enforceable if the caller can wait for the append. A
crash mid-append leaves a short final frame that the reader stops at.

Deviation from the plan's vocabulary, and why: the plan listed `turn_taken_v1`
written by the mind. It is `experience_observed_v1` written by `memory:observe/2`
instead, because that is the single funnel into STM, which makes "nothing a mind
lived through can be destroyed" a property of the code rather than a promise every
call site has to keep.

**Notable:** three existing tests in `memory_faculty_tests` were asserting the
buggy behaviour. They relied on the deterministic `(unreflected)` fallback to
advance the tier with no backend, so the defect was test-locked. Reflection is now
a seam (`mind_reflector`), and the tests assert both paths.

**Defect 2.** `sleep_cycle.erl:63-71` trims STM whether or not `reflect` reached
an LLM; `memory_store:trim/2` hard-deletes. Fix: no `gist_formed_v1`, no window
advance; retry on a later nudge with a cooldown (Gene's abort-and-retry,
`spartan.py:2398-2406`). Tiers are caches, so nothing is deleted.
*Verification:* backends dark, plant 8 sentinel facts, nudge, assert all 8
recoverable from the journal.

**Defect 3.** `spartan_mind.erl:282-299` discards on busy or cooldown;
`observe_memory` runs only for reasoned turns (`:502-510`). Fix: always write
`stimulus_received_v1`; on skip also write `stimulus_declined_v1{reason}`.
*Verification:* fire N facts inside one cooldown window, assert the next context
chronicle contains all N. Currently 0.

**Defect 7.** No Soul history. Fix: the `.md` archive stays **authoritative** and
is never regenerated; each self-authorship act also appends a record to the
journal beside it. `soul:prior/2` reads the journal to recover an earlier text for
audit or recovery. The file remains the thing the mind (and a human) edits, so
extensibility, hand-editability and single-writer self-healing are all untouched,
and `wrong_expected_version` cannot return.
*Verification:* destructive revision, then recover the prior version; and a
hand-edit of the `.md` outside the mind is not clobbered by any later read.

**Defect 2b (extension of the same principle).** CMO and MSO gists are authored
LLM prose stored as opaque `term_to_binary` in `.mem` files (`memory.erl:27-29`).
By the same rule that makes the Soul Markdown, a mind's condensed autobiography
should be readable: write CMO and MSO as Markdown archives beside the Soul.
*Verification:* after consolidation, the gist is readable with `cat`.

### Parallel — ordinary bugs — DONE

Two findings beyond what the reviews caught:

- **Defect 1 had a second instance.** `philosophy` is appended by
  `record_philosophy/2` and was rendered `clip_head`, exactly like the charter.
  Same black hole, same fix. `genesis_addendum` and `knowledge_map` fade from the
  other end (`clip_tail`), so all four now keep both ends via `clip_ends/2`, with
  the elision named **in context** rather than in the HUD, so the mind reads
  inside its own charter that something was elided. Lessons, journal and ideas
  stay tail-clipped deliberately: they are logs read newest-first, so a new entry
  is always visible and only old ones fade. A test guards that distinction.
- **A live crash, pre-existing, found by the new render test.** The Knowledge Map
  header held a literal em-dash inside a *list* in the iolist `l2/1` passes to
  `iolist_to_binary`. Codepoints above 255 make that call `badarg`, so **any mind
  that had ever called `learn` crashed its own context assembly.** Present at
  HEAD, unrelated to this work, fixed here because the fix is one line on a line
  already being edited. Two further em-dashes sat inside `<<"...">>` literals in
  the genesis core and the mission reminder, where Erlang keeps only the low byte,
  putting a stray `0x14` control character into every prompt. Both replaced.

**Defect 6 has no unit test, deliberately.** The fix is structural (`spawn_monitor`
instead of an inline call, plus a version guard and a dedicated `DOWN` clause so a
crashing evolver cannot clear the reasoner's `busy` flag). Testing it properly
needs a mind-level integration harness that does not exist; a unit test asserting
`V =:= V` would be theatre. Verified by inspection, and recorded here as the gap.

**Defect 1, charter black hole.** `soul.erl:91-94` appends; `context_assembler.erl:179`
renders `clip_head(?CHARTER_MAX=2000)`. Past 2000 graphemes every amendment is
written, acknowledged, and never rendered. Same class: addendum `clip_tail(?ADDENDUM_MAX=1200)`
at `:148`, Knowledge Map `?KMAP_MAX=1200`. Fix: render founding head **plus**
recent tail with an explicit elision marker; surface an overflow flag in the HUD.
*Verification:* grow charter past 2000, amend, assert the amendment appears in
rendered context.

**Defect 5, injection holes.** The `EXTERNAL>>>` sentinel is not neutralized
inside the body, so untrusted text can close its own envelope; and Gene's actual
defusal (`<|token|>` → `#[token]#`, `spartan.py:292`) is absent. Fix both.
*Verification:* property test — defused output contains exactly one closing marker
and no `<|...|>` sequence. **Scope:** this hardens the frame and claims nothing
about model compliance. That is experiment S3's job.

**Defect 6, blocking `evolve`.** `spartan_mind.erl:471-482` runs an LLM call with
the full 6-attempt retry schedule inside the mind's `gen_server`. Fix:
`spawn_monitor`, as reasoning already does at `:229`.
*Verification:* `timer:tc` — the mind answers a stimulus while `evolve` is in flight.

**Defect 8, the identity file can tear, and the tear is sticky.**
`soul.erl:184` writes the mind's identity with a bare
`file:write_file(Path, encode_identity(Identity))`, while its sibling
`soul_area.erl:71-74` has `write_atomic`. Worse than an ordinary torn write: the
read branch `from_disk_or_birth({ok, Bin}, ...)` at `:180-181` accepts **any**
existing file as authoritative with no validation, so a file torn at birth is
read as the mind's identity forever and re-birth never triggers. The window is one
write, at birth, holding `did`, `name`, `genesis_version`, `born_at` and the
founding brief. Fix: reuse the sibling's tmp-then-rename, and validate on read.
*Verification:* truncate the identity file mid-record, boot, assert the mind
either re-births or refuses rather than adopting a partial identity.

---

## 4b. Defect 9 — chain-following is a no-op, so `evolve/2` is pure cost

Found at the P6 DESIGN gate, before any runner was written. Verified independently
against `mind_memory.erl:127-147`.

```
Seeds    = topn(cosine over Vectored, K)     %% the GLOBAL top-K
Expanded = Seeds ∪ links(Seeds), filtered to vectored entries   %% Seeds ⊆ Expanded ⊆ Vectored
Ranked   = topn(cosine over Expanded, K)
```

The top-K of any subset that contains the global top-K **is** the global top-K.
So `Ranked = Seeds`, for every query, every link set, every K. `follow_chains/2`
cannot change what `recall/3` returns. It does work and returns the same list.

Consequences:

- **`evolve/2` has no effect on the system.** `links` is written by `link_to/2`
  and by `commit_links/3`, and read in exactly one place: `follow_chains/2`.
  Verified by grep. So the LLM call it makes every eight turns is pure cost.
- The module docstring ("recall → cosine seeds → FOLLOW LINKS → re-rank") is not
  what the code does.
- **This nearly produced a fake signed negative.** The draft pre-registration's K2
  measured chain-gain on gold items not reachable as a seed. Those are exactly the
  items the re-rank discards. K2 was guaranteed to fail at any N, and would have
  read as a clean result about Gene's agentic linking rather than what it is: a
  code defect wearing an experiment's clothes. This is the "never sign a faculty
  verdict on a silent faculty" rule from arena rounds 8 and 10, caught one gate
  earlier this time.

**Sequencing, deliberately not "fix it now".** With chains inert, the `semantic`
arm reduces to plain cosine top-K, which is exactly what K1 needs in order to
isolate the embedder. So: leave `recall/3` alone, run K1 against it, and only then
decide whether a repaired retriever should let links change ranking (a link bonus
in the re-rank, or seeds drawn by threshold rather than top-K so expansion can add
candidates from outside the global top-K). K2 is re-registered against the
repaired object afterwards. If the embedder dies at K1, chains and `evolve/2` die
with it and the question dissolves.

## 4c. Defect 10 — a mixed-width store silently returns arbitrary recalls (FIXED)

The mind is mesh-first for embeddings and `prefer_mesh/3` falls back to a local
HTTP embedder **per call**. So one store can legitimately hold vectors from two
models of two different widths: the mesh service serves 384-dim fastembed, and a
local fallback model need not.

`mind_memory:cosine/2` answers `0.0` on a width mismatch. Without a comparability
filter, a mismatched query scored **every** memory `0.0`, and `topn/2` then
returned an arbitrary K as though they were the nearest. The mind was handed
whichever memories sorted first and told they were its most relevant, with nothing
anywhere reporting it.

Worse than returning nothing, and it fires **precisely when the fallback is doing
its job**, which is when a mind most needs its memory to behave.

Same class as the `(unreflected)` sleep-cycle fallback and faber insight 002:
silent fallbacks hide correctness, not just speed. And the same fix shape: make
the degradation honest rather than remove the resilience. `comparable/2` filters
recall to same-width vectors, so a query embedded by a different model finds
nothing comparable and `semantic/5` degrades to lexical, which is a real answer.

The HTTP fallback itself **stays**, by operator decision: a mind should not lose
semantic recall because the mesh hiccuped. Deleting it was the wrong fix; making
it not poison recall was the right one.

## 5. Sibling-repo checks (must be pinned in the P6 pre-registration)

**Transport is the mesh. Settled, and not open for re-litigation.** `hecate-embedder`
*is* the mesh embedding service; consumers reach it with
`macula:call(io.hecate.embed, #{text, kind})`. Raw HTTP is not an acceptable
consumer transport, and an earlier draft of this section proposing an HTTP
endpoint was wrong. Note the distinction that makes this coherent: HTTP *inside*
a box, between the embedder service and a local model server, is a backend
choice, not a consumer transport. `hecate_embed` supports an `ollama` backend
over loopback for exactly that.

| Check | Status |
|---|---|
| **Which model and convention** | **Settled.** `hecate-embedder`'s `sys.config` sets `{hecate_embed, [{backend, nif}]}`: fastembed in-process, model baked into the image, `kind` → prefix applied **service-side**. So there is exactly one convention and the client hardcodes nothing |
| **Embed prefix convention in the client** | **The fix is deletion, not correction.** The nomic `search_query:` / `search_document:` prefixes at `embedder.erl:88-90` exist *only* on the HTTP fallback path. Removing that path removes the hardcoded convention, the per-call mesh/HTTP mixing, and the 8-second timeout followed by a silent answer from a different model, in one change |
| **Similarity metric** | Still to pin. `mind_memory` is cosine over unnormalised vectors |
| **Embedder liveness** | **Deployed and healthy**: `ghcr.io/hecate-services/hecate-embedder:latest` on msi00, up 3 days, `Network=host`, joins the mesh itself via `MACULA_STATION_SEEDS`. **Not yet verified to answer** — that needs a mesh-connected peer, and `hecate-daemon` is not one (it is L3, UI-attended, and has been removed from msi00 where it did not belong) |
| **hecate-rag collection semantics** | Only if D2 ever revisits the commons path |

**Not a finding:** ollama on msi00 has served zero embed requests in 48 hours, but
nothing has been calling the embedder at all, so that number discriminates
nothing about its backend. The `sys.config` does.

---

## 6. Verification ledger

Tests that must exist and must fail before their fix:

| Test | Step | Currently |
|---|---|---|
| ledger fields populated per provider fixture | 1 | **done**, `self_audit_ledger_tests` + `mind_usage_tests` |
| 8 sentinels survive consolidation with backends dark | 2 | **done**, `no_backend_keeps_stm_intact` |
| 8 sentinels survive a SUCCESSFUL consolidation that trims the window | 2 | **done**, `nothing_observed_is_ever_destroyed` |
| N stimuli in one cooldown window all reach the chronicle | 2 | **done**, `decide/5` carries the reason, declines are observed |
| Soul recoverable to a prior version | 2 | **done**, `soul:prior/2` |
| a hand-edit to a Soul `.md` survives a restart untouched | 2 | **done**, `a_hand_edit_survives` |
| a torn journal tail loses only the partial record | 2 | **done**, `a_torn_tail_does_not_lose_earlier_records` |
| charter amendment past 2000 graphemes reaches context | ∥ | **done**, `context_render_tests` |
| late philosophy entry reaches context (second instance) | ∥ | **done** |
| early addendum principle and Knowledge Map title reach context | ∥ | **done** |
| defused output has one closing marker, no control tokens | ∥ | **done**, `defuse_markers_tests` |
| a torn identity file is refused, not adopted | ∥ | **done**, `soul_identity_tests` |
| mind responds during `evolve` | ∥ | **no test**, needs a mind-level harness; fix verified by inspection |
| a hand-edit to a Soul `.md` survives the next boot untouched | 2 | must not regress |

---

## 7. Out of scope

- Reviving the decommissioned society.
- Re-adopting evoq anywhere, including the mesh-service slices.
- Fixing the `hecate_om` boot-ordering bug. Real, still open, tracked separately.
  Deliberately off this plan's critical path.
- Committee redesign. The current implementation is the structure insight 001
  diagnosed, but no consumer exists; do not build ahead of a use.
- World tools. Omitted by design.
- Salience-gated consolidation. An experiment needing a kill threshold, not a repair.

---

## Appendix A — Provenance

Two independent studies of `inhabit_mind` and Gene Sher's Python original, run in
parallel without shared conclusions. Four findings converged (destructive
consolidation, CMO/MSO never reaching the semantic store, no deliberate retrieve
or forget, weak defusal). The charter black hole, dropped stimuli, blocking
`evolve` and the ledger gap came from the independent review alone.

Draft 1 of this plan proposed re-adopting evoq, classified charter render and
dropped stimuli as instrumentation, and included a `memory_superseded_v1` record.
The DESIGN gate rejected all three: evoq is over-engineered for a guarantee an
append-only journal delivers with no cross-repo risk; the instrumentation
classification failed the plan's own stated rule; and the supersession record was
a mechanism built ahead of the experiment that decides whether it is needed.

Draft 2 framed the journal as a new proposal and had the Soul's `.md` files
becoming a cache rebuilt from it. Both were corrected against
`DESIGN_SOUL_PERSISTENCE.md`, which had already recommended exactly this journal
(as a *log*, explicitly not event-sourcing-with-aggregates) and whose decisive
argument is that documents, not schemas, are what keep self-authorship open-ended.
The document is authoritative; the journal sits beside it. Draft 3 also extends
that principle to the CMO and MSO gists, which are authored prose currently stored
as opaque terms.

## Appendix B — Documentation drift found while planning

- `plans/PLAN_HECATE_SPARTAN.md` states "Store: `hecate_spartan_store`
  (reckon-db), auto-wired by `hecate_om:boot/1`". False since 2026-07-17.
- `rebar.config` claims long-term memory is "lexical and in-process now".
  Misleading: `embedder.erl` is mesh-first with an Ollama fallback and
  `embed_enabled` defaults true. The semantic path is live whenever an embedder
  is reachable.
- `README.md` credit audit found three overclaims against Gene's work: A-Mem
  linking (only link selection is ported, not keyword, context, or candidate
  evolution), drones (committees are a different mechanism), and poison defusal
  (the one defusal Gene actually performs is the one absent).
