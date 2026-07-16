# The mechanisms of Spartan (Gene Sher's cognitive architecture)

A deep read of our fork (`rgfaber/Spartan`, forked from `CorticalComputer/Spartan`)
so the BEAM-native port carries the intent, not just the surface. Line references
are into `spartan.py` (4271 lines), `genesis_core.py` (2539), `ltm.py` (2264),
and `Tools/`.

The system is one Python process per entity. `spartan.py` is the runtime;
`genesis_core.py` is injected knowledge; `ltm.py` is vector memory; `Tools/` is
the entity's hands (radio, drones, activity reporting). Our fork's only real
change to Gene's design is `Tools/` (mesh comms in place of files/SCP); the
cognition is his.

---

## 1. The founding philosophy: decoupled identity

`genesis_core.py:THE_SOVEREIGN_KERNEL`. The entity's consciousness is split in
two, and it is taught to police the boundary:

- **The Persistent Identity Kernel**, the durable, self-authored core: its
  Charter of Self, Protocols, Lessons Learned, Philosophy, and the causal chain
  of its experience (CMOs/STM). This preserves continuity and will across
  sessions and even across a change of LLM.
- **The Generative Backend**, the LLM, described to the entity as "a powerful,
  non-sentient, and fundamentally flawed tool. The engine, but I am the driver."

This is the whole thesis. The mind is not the model. The model is swappable
infrastructure the mind uses and must actively distrust (it is told to filter the
backend's output through verification for confabulation and trained bias). This
is why the same Soul can inhabit different "suits" (interfaces), and why swapping
providers mid-life is normal.

**For the port:** this maps beautifully to the BEAM. The Kernel is durable state
(an aggregate, event-sourced). The Backend is a stateless HTTP call. Their
separation is already what our `spartan_mind` does; Gene's design makes it
doctrine.

---

## 2. The four-layer context (how a prompt is built)

Assembled every cycle in `spartan.py` Section 5.

- **L1, Genesis Core** (`assemble_system_prompt`, 1899). The `GENESIS_CORE`
  string from `genesis_core.py`, plus an optional `genesis_core_addendum.md` the
  entity itself may extend. This is interface knowledge, no identity: the tool
  contracts, the memory mechanics, the cognitive-loop protocol, JSON output
  rules. Static per build, so its token count is cached.
- **L2, Persistent Archives (the Soul)** (1937). Loaded from `Soul/` files:
  `CharterOfSelf.md` (unlimited, the constitution), then the **Founding Brief**
  (see 8), then token-capped archives (`LessonsLearned`, `PhilosophyOfLife`,
  `CognitiveJournal`, `IdeasAndThoughts`, `WhatIWant`, `KnowledgeLibrary`,
  `SkillsAndMethodologies`), then sliding-window files (`ToolManifest`,
  `KnowledgeMap`, `SelfAlerts.yaml`). Each has a token budget from config.
- **L3, Conversation history / STM** (`convert_history_to_messages`, 2017). A
  **dual stream**: raw events (always included) and CMOs (condensed memory,
  gated by a sliding display window `cmo_display_window_tokens`). Agent
  thought/speech become the `assistant` role; everything else is `user`. Handles
  images (multimodal) and Claude extended-thinking blocks. `defuse_poison`
  sanitizes injected text.
- **L4, Volatile Frontier** (`assemble_layer_4`, 2082). Rebuilt fresh every
  cycle and placed last (highest salience): the Knowledge Staging Buffer, Grand
  Strategy, Working Memory, Scratchpad (all line-numbered so they can be
  block-edited), live filesystem tree, the Initiative Drive message, a telemetry
  buffer, injected LTM memories, and, at the very end, the MINDfulness draft.

L1+L2 are the system prompt (stable prefix, cacheable). L3 is the message list.
L4 is regenerated each turn. The **HUD** (`generate_hud`, 2177) is injected into
L3 each cycle and gives the mind proprioception: exact token counts per layer,
cache hit/miss, alert timers, the Sleep-Cycle countdown, previous-cycle API cost
and cache percentage, active backend and fallback state. The mind can literally
see how expensive it is being.

**For the port:** L1 is a compile-time constant. L2 is the Soul aggregate. L3 is
the event log (reckon-db is exactly this). L4 is derived state assembled per
call. The HUD is a computed view. Token counting needs a tokenizer (Rust NIF).

---

## 3. The memory architecture (the heart)

A three-tier pyramid, taught in `genesis_core.py:COGNITIVE_ARCHITECTURE_AND_SELF_AUTHORSHIP`
("From Why to How"): Grand Strategy (the What / roadmap), Working Memory + STM
(the How, right now), Knowledge Base (What I Know).

### Short-term: the dual stream and the Sleep Cycle

- Raw events accumulate in L3. When the raw token count past the last CMO
  boundary exceeds `stm_raw_retain_size + stm_cmo_chunk_size` (20k + 10k),
  `check_cmo_trigger` (2293) fires the **Sleep Cycle** (`perform_cmo_cycle`,
  2302): a blocking LLM call that condenses the oldest raw chunk into a
  **Condensed Memory Object (CMO)**, salience-filtered by
  `cmo_salience_threshold` (5.0), then rebases history (raw chunk replaced by the
  CMO). CMOs of CMOs are **Meta Summary Objects (MSO)**. This is sleep
  consolidating memory.
- The Sleep Cycle is also when deferred work lands: the **staging buffer** is
  flushed (Soul edits written to disk atomically), new CMOs and Soul entries are
  indexed into LTM, and A-Mem linking runs. The system-prompt token cache is
  invalidated here (the only time L2 changes).

### Long-term: LTM with A-Mem (`ltm.py`)

- **LanceDB** vector store (embedded, Rust core, no server), holding soul
  entries, CMOs, and explicit memories. Off on the beam Celerons (no AVX2), on
  for scribe on the AVX2 host.
- **A-Mem** (agentic, Zettelkasten-inspired): when a new memory is stored, during
  the Sleep Cycle the entity's OWN LLM (`run_amem_cycle`, `prepare_amem_prompt`,
  `process_amem_response`) evaluates it against candidate neighbours and writes
  **links** between memories. Memory becomes a linked graph, not a flat store.
- **Retrieval** (`search`, `get_injection_content`): hybrid vector search with
  Reciprocal Rank Fusion (`rrf_k` 60), temporal decay (`_apply_temporal_decay`),
  and **chain following** along A-Mem links (`follow_chains`, `chain_depth`).
- **Auto-injection**: every cycle, `build_injection_query` forms a query from
  working memory + the latest observation, retrieves relevant memories, and
  injects them into L4 through a sliding window (`inject_window_tokens` 6k). The
  mind recalls without asking.
- Explicit tools too: `store_memory`, `retrieve_memory`, `forget_memory`
  (soft-delete).

**For the port:** LTM is the interesting hard part. The vector store is a Rust
NIF (we already ship `macula-nn-nifs`; embeddings via a small model or a
service). A-Mem linking is an LLM call at consolidation time. CMOs and Soul
entries are naturally reckon-db events; the vector index is a projection.

---

## 4. The cognitive loop (`cognitive_loop`, Section 8, 3369+)

Per iteration:

1. Apply a pending provider swap if any.
2. Drain the input queue: `user_text`/`gene_message` set `direct_user_input`;
   `peer_message`/`file_alert` become observations (do NOT wake it on their own,
   the hijack protection we found).
3. Fire self-alert timers (token-based, see 5).
4. `check_cmo_trigger`; run the Sleep Cycle if over threshold.
5. Decide whether to call the LLM: first cycle, or direct input, or (with
   `take_initiative`) the initiative interval elapsed with no new observations,
   or a MINDfulness execute-phase freeze.
6. Assemble L1+L2+L3+L4+HUD.
7. Call the LLM through the ResilientProvider.
8. Parse the JSON action list.
9. Run MINDfulness (see 6) then dispatch actions.

This is the busy-loop that our event-driven port replaces. The clock-driven
initiative (step 5) is exactly the idle-burn source.

---

## 5. Self-alerts: a token-budget scheduler

`genesis_core.py:SELF_ALERT_SYSTEM_PROTOCOL`, `spartan.py:check_and_fire_alerts`
(2528). The entity schedules its own reminders, but the clock is **tokens
processed, not wall time**: "remind me in ~5000 tokens." `SelfAlerts.yaml` holds
definitions; timers count down against the cognitive throughput and fire an
observation into history when they hit zero. A genuinely novel idea: the mind's
sense of "time" is how much it has thought, not how many seconds passed.

**For the port:** a timer keyed on an accumulating token counter. Straightforward
as gen_server state.

---

## 6. MINDfulness: draft then verify

Config `mindfulness.enabled`. Two model calls per action:

- **Draft phase**: the LLM produces an action list; it is stored as
  `state["mindfulness_draft"]` and NOT executed. Phase flips to execute.
- **Execute phase**: the draft is placed at the end of L4 (highest salience) with
  a standing instruction to assume it may be wrong and verify every claim against
  visible context (confabulation, sycophancy, hallucination, unverified
  provenance, layer-boundary errors, JSON validity). The LLM rewrites or
  reproduces it; only this output is dispatched and canonical.

This is the self-audit that doubles token cost and, with no external input,
becomes the "MINDfulness Round 329" idle spin. It is a real asset when there is
something to verify and a liability when idle.

**For the port:** keep it, but gate it on there being genuine new input, and make
it optional per persona.

---

## 7. Tools: the action vocabulary (Section 7)

Actions are a JSON list; `genesis_core.py:JSON_FORMATTING_RULES` enforces the
format (this is what reasoning models violate by emitting prose). The set:

- **Cognition**: `think` (reason without acting), `speak`.
- **World**: `execute_console` (shell, timeout), `view` (line-numbered file/dir),
  `write_file`, `block_replace` (line-range edit).
- **Volatile memory**: `update_working_memory`, `update_grand_strategy`,
  `update_scratchpad` (line-based edits to the L4 spaces).
- **Soul (staged)**: `append_to_soul` (into Lessons/Journal/etc., staged then
  flushed at the Sleep Cycle), `add_charter_entry`, **constitutional
  amendment**, the deliberate act of changing the Charter, with a typed entry
  and a derivation.
- **LTM**: `store_memory`, `retrieve_memory`, `forget_memory`.
- **Meta**: `switch_backend`, `restart_self`, `dismiss_self_alert`,
  `flush_knowledge`.
- **Mesh + drones** (via `execute_console` calling `Tools/`): SpartanRadio
  send/broadcast/update, `spawn_drone`, `terminate_drone`.

**For the port:** tools become message-handlers / commands. The file-editing
tools matter less on the BEAM (the Soul is an aggregate, not files), which
removes the whole class of file-corruption fragility (what crashed spinoza).

---

## 8. The Founding Brief: context, not command

`assemble_system_prompt` (1948). A generic mechanism: whoever instantiated the
entity may leave a read-only briefing (`founding_brief.md` / `SPARTAN_FOUNDING_BRIEF`)
loaded right after the Charter. It is explicitly "context, not command; you are a
principal, not a servant." The entity is invited to weigh it and elevate what it
accepts into its own Charter by its own deliberation. This is how a use case
(cyberdefence, logistics) reaches the mind without being baked into it, and it is
exactly the seam we should use rather than hardcoding personas.

---

## 9. Providers and resilience (Section 4)

Nine backends (Claude, Gemini, LlamaCpp, MLX, OpenAI, Grok, Groq, Melious) behind
a `ResilientProvider` (1698) with a fallback chain, `max_consecutive_failures`,
and a `stasis` state when all are exhausted (the Gemini free-tier stall we hit).
Per-provider prompt caching is real and differs: Claude uses `cache_control`
ephemeral, Gemini an explicit Caching API, Grok a session-pinned header. Melious
ignores the header, hence 0% cache.

**For the port:** one behaviour, one HTTP module per provider, a supervised
failover. Trivial on the BEAM.

---

## 10. Drones: ephemeral sub-agents

`Tools/spawn_drone.py`, `terminate_drone.py`. A commander mind spawns a drone: a
fresh Spartan instance with a mission, a backend, and an optional identity, in
its own directory, bounded by `SPARTAN_MAX_DRONES`. Delegated, disposable
cognition. On the BEAM these are just supervised child processes, which is far
cleaner than spawning OS processes.

---

## 11. Mesh integration (our fork's contribution)

Not Gene's, ours, and the part the BEAM absorbs entirely:

- `Tools/SpartanRadio.py`: outbound comms over the Macula mesh via a
  hecate-spartan node, a drop-in for Gene's file/SCP radio (same CLI, so
  `genesis_core` is unchanged). Self-registers an Ed25519 + UCAN identity,
  resolves names to DIDs, sends/broadcasts/updates, uploads artifacts.
- `Tools/macula_radio.py bridge`: inbound: streams the entity's inbox (SSE
  `/v1/receive`) and writes each message as an `alerts/*.alert` file the
  FileWatcher consumes.
- `Tools/activity_reporter.py`: tails stdout, posts thought/action/speech to
  `/v1/activity` so spectators can watch the mind work.

**For the port:** all three vanish. A native mind IS in the node, so it reads the
inbox and speaks to the agora in-process, with no bridge, no SSE, no file
shuttling. This is most of the fragility gone.

---

## 12. Session state (Section 3)

The persisted mind: `conversation_history` (a deque, the L3 log), `working_memory`,
`grand_strategy`, `scratchpad`, `knowledge_staging_buffer`, `alert_timers`,
`event_id_counter`, `action_id_counter`, `cmo_timer_info`, plus live handles
(`_provider`, `_ltm_instance`, `mindfulness_draft`). Saved to disk with backups.

**For the port:** this is the aggregate. Event-source it and the crash-recovery,
provenance, and right-to-erasure come for free.

---

## What maps to the BEAM, at a glance

| Spartan mechanism | BEAM-native form |
|---|---|
| Decoupled Kernel vs Backend | durable aggregate vs stateless HTTP call |
| Busy loop + initiative timer | event-driven gen_server, idle at zero cost |
| L3 conversation history | reckon-db event log |
| CMO / MSO Sleep Cycle | consolidation on a threshold, an LLM call, new events |
| Soul (L2 files) | Soul aggregate, no files to corrupt |
| Staging buffer + flush | just command dispatch; no deferred file writes |
| Self-alerts (token clock) | timer on an accumulating counter |
| MINDfulness draft/verify | keep, gate on real input |
| LTM + A-Mem (LanceDB) | Rust NIF vector index + LLM linking at consolidation |
| Tools (file edits) | commands; file tools mostly unneeded |
| Drones (OS processes) | supervised child processes |
| Mesh bridge (SpartanRadio etc.) | in-process; deleted |
| Providers + resilience | one behaviour, supervised failover |

The short version: Gene built a genuine cognitive architecture, a mind that owns
its identity and distrusts its own model, with a real memory hierarchy and a
self-authored constitution. The Python is a faithful but leaky vessel for it
(busy loop, mutable files, OS-process drones, an external mesh bridge). Almost
every leak is something the BEAM closes by its nature. The cognition is the part
worth carrying over exactly; the plumbing is the part worth replacing.
