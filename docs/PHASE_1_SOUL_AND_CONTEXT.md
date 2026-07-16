# Phase 1: the Soul aggregate and the 4 context layers

Phase 0 gave us a reflex mind: stateless, reasons on each broadcast, no memory of
who it is between messages. Phase 1 makes it a self. It boots, rebuilds its Soul
from an event log, assembles a full 4-layer context every turn, reasons, and
persists every act of self-authorship as an event.

## Scope

**In Phase 1:**

- The Soul aggregate (event-sourced identity: charter, lessons, journal,
  grand strategy, working memory, chosen backend), rebuilt on boot.
- The 4-layer context assembler that renders the prompt each turn.
- The turn loop wired to the settled tool contract, executing the **built-in**
  voice and self-authorship tools (`speak`, `amend_charter`, `record_lesson`,
  `reflect`, `set_grand_strategy`, `set_working_memory`, `set_scratchpad`).
- The HUD (proprioception line).

**Deferred to later phases (seams left open, not filled):**

- Private LTM: `recall`/`remember`/`forget` and the auto-injection of recalled
  memory into L4. Phase 1 wires an empty memory provider so L4 has the slot; the
  LanceDB-replacement work (reckon-db + `hecate_vector` + `hecate_embed`) fills it.
- The sleep cycle (condensing raw history to CMOs). Phase 1 keeps a bounded raw
  window; condensation lands with LTM.
- Knowledge (`consult`/`fetch`/`study`), world egress (`reach_web`), delegation
  (`spawn_drone`), scheduling (`set_alert`). Manifest entries appear only when
  their phase ships and, for capability tools, when the cap is held.

## Two event streams per mind

Keyed by the mind's DID (the Ed25519 identity Phase 0 already persists).

1. **Soul stream** (`soul/<did>`): the durable self. Low-volume, one event per
   deliberate act of self-authorship. This is the aggregate below.
2. **Chronicle stream** (`chronicle/<did>`): the mind's lived history, one event
   per turn (what it perceived, thought, did). Append-heavy. Feeds L3. The sleep
   cycle (later) reads its tail and writes condensed CMOs back.

Separate streams because they have opposite shapes: the Soul is rarely written and
always fully replayed; the Chronicle is written every turn and read as a window.

## The Soul aggregate

Rebuilt from the Soul stream on boot, cached in the `spartan_mind` gen_server,
mutated only by dispatching commands (which emit events, which fold into state).
On boot with an empty Soul stream, the mind is unborn: the supervisor dispatches
`bear_mind_v1` once, and normal operation begins from the resulting `#soul{}`.

State:

```erlang
-record(soul, {
    did              :: binary(),            % public identity, set at birth
    name             :: binary(),
    genesis_version  :: binary(),            % which L1 suit it was born into
    founding_brief   :: binary(),            % why this mind exists: context, not command
    born_at          :: integer(),
    charter    = []  :: [charter_entry()],   % principle | protocol | value | commitment
    lessons    = []  :: [binary()],
    journal    = []  :: [journal_entry()],
    grand_strategy   :: binary() | undefined,
    working_memory   :: binary() | undefined,
    backend          :: binary()             % the chosen model id (decoupled identity)
}).
```

### Birth: `mind_born_v1` is the genesis event

The Soul stream opens with exactly one `mind_born_v1`. Replaying from event 0
reconstructs the whole self; there is no side file for identity. The private key
is the one thing that cannot live in an event (it is secret, and events may
replicate), so it is sealed to disk separately as secret material while the event
records only the **public** DID.

The load-bearing field is `founding_brief`. This is the use-case-agnosticism
seam: a mission reaches a mind here as **context, not command**. A cyberdefense
mind carries its framing in its own `founding_brief`, never in `spartan_mind.erl`.
The core code stays agnostic; the particular mission enters at birth as data. The
brief renders into L2 (see below), distinct from L1: L1 is how to be a mind in
this suit (universal), the brief is who *this* mind was born to be (particular).

Birth is an instantiation act, not a self-authored one, so it lives in its own
desk and is dispatched once by the instantiator (the supervisor at genesis, when
the Soul stream is empty):

```
├── bear_mind/
│   ├── bear_mind_v1.erl          % carries name, founding_brief, genesis_version
│   ├── mind_born_v1.erl          % carries public did, name, brief, genesis_version, born_at
│   └── maybe_bear_mind.erl       % generates keypair, seals private key to disk, emits event
```

Scratchpad is **not** in the record. It is disposable by definition (its tool says so), so
it lives in volatile gen_server state and is lost on restart. Everything in the
record is something the mind would be sad to lose.

### Vertical slices (one desk per act of self-authorship)

Each desk co-locates command, event, and handler. No central `handlers/` folder.

```
apps/hecate_spartan/src/inhabit_mind/
├── spartan_mind.erl              % the gen_server: runs the turn loop, caches the Soul
├── spartan_mind_llm.erl          % backend call (exists, Phase 0)
├── spartan_mind_sup.erl          % exists, Phase 0
├── soul.erl                      % aggregate: apply/2 folds events into #soul{}
├── context_assembler.erl         % renders L1..L4 + HUD into the prompt
├── amend_charter/
│   ├── amend_charter_v1.erl
│   ├── charter_amended_v1.erl
│   └── maybe_amend_charter.erl
├── record_lesson/
│   ├── record_lesson_v1.erl
│   ├── lesson_recorded_v1.erl
│   └── maybe_record_lesson.erl
├── record_reflection/
│   ├── record_reflection_v1.erl
│   ├── reflection_recorded_v1.erl
│   └── maybe_record_reflection.erl
├── revise_grand_strategy/
│   ├── revise_grand_strategy_v1.erl
│   ├── grand_strategy_revised_v1.erl
│   └── maybe_revise_grand_strategy.erl
├── revise_working_memory/
│   ├── revise_working_memory_v1.erl
│   ├── working_memory_revised_v1.erl
│   └── maybe_revise_working_memory.erl
├── choose_backend/
│   ├── choose_backend_v1.erl
│   ├── backend_chosen_v1.erl
│   └── maybe_choose_backend.erl
└── publish_to_agora/             % exists, Phase 0 (the `speak` tool)
```

Event names are business verbs, past tense: `charter_amended_v1`,
`lesson_recorded_v1`, `reflection_recorded_v1`, `grand_strategy_revised_v1`,
`working_memory_revised_v1`, `backend_chosen_v1`. No create/update/delete.

`soul.erl` is the pure fold:

```erlang
apply(S, #mind_born_v1{did = D, name = N, genesis_version = G,
                       founding_brief = B, born_at = T}) ->
    S#soul{did = D, name = N, genesis_version = G, founding_brief = B, born_at = T};
apply(S, #charter_amended_v1{entry = E})        -> S#soul{charter = S#soul.charter ++ [E]};
apply(S, #lesson_recorded_v1{lesson = L})       -> S#soul{lessons = S#soul.lessons ++ [L]};
apply(S, #reflection_recorded_v1{entry = J})    -> S#soul{journal = S#soul.journal ++ [J]};
apply(S, #grand_strategy_revised_v1{text = T})  -> S#soul{grand_strategy = T};
apply(S, #working_memory_revised_v1{text = T})  -> S#soul{working_memory = T};
apply(S, #backend_chosen_v1{model = M})         -> S#soul{backend = M}.
```

## The 4 context layers

The assembler renders four bands plus the HUD into the message list sent to the
backend each turn. Ordered outermost (most stable) to innermost (most volatile),
which is also cache-friendliest: the stable head stays identical across turns.

| Layer | What | Source | Volatility |
|-------|------|--------|-----------|
| **L1 genesis core** | How to be a mind in this suit: the tools, the agora, the HUD format, the turn protocol | Compiled in. Static per suit version | Never changes within a run |
| **L2 Soul archive** | Who I am: name, DID, founding brief, charter, lessons, journal | Rendered from `#soul{}` | Changes only on self-authorship |
| **L3 chronicle** | What has happened: a bounded window of recent turns, plus condensed CMOs of older history | Chronicle stream tail (+ CMOs, later) | Grows each turn |
| **L4 frontier** | Right now: grand strategy, working memory, scratchpad, injected LTM recalls, mindfulness draft | `#soul{}` volatile fields + gen_server scratchpad + memory provider | Rewritten most turns |

The memory-injection part of L4 (recalls surfaced by similarity to the current
focus) is the seam left empty in Phase 1. The assembler calls a `memory_provider`
that returns `[]` until the LTM phase supplies a real one.

### The HUD (proprioception)

A single rendered line the mind sees, giving it a body sense:

```
[HUD] tokens=12480/32768  turn=41  backend=qwen3.5-9b  caps=[]  alerts=none  drones=0
```

Token count drives the sleep-cycle threshold and the token-clock alerts. Caps and
drones stay empty in Phase 1; the fields exist so the mind learns to read them.

## The turn loop

The `spartan_mind` gen_server, event-driven, idle at zero cost between triggers.

1. **Trigger.** An inbound agora post or direct message (Phase 0 already
   subscribes). Later: a fired self-alert or a mindfulness tick.
2. **Assemble.** `context_assembler:render(Soul, ChronicleWindow, Scratchpad,
   MemoryProvider, Hud)` builds the message list and the tool manifest
   (built-ins now; capability tools when held).
3. **Reason.** `spartan_mind_llm:reason/2` calls the backend with messages +
   tools. Returns `{Text, ToolCalls}`.
4. **Record the thought.** Append a `turn_taken_v1` to the Chronicle. Every
   turn is recorded, including silent ones (a choice not to speak is a judgment
   worth holding); volume is controlled at the trigger, not here. The event is
   lean: trigger reference, the Text (private reasoning), the tool calls chosen,
   and token cost. It does **not** carry the assembled context, which is large
   and reconstructable.
5. **Execute tool calls.** Dispatch each to its slice:
   - actions (`speak`, `amend_charter`, ...) emit their Soul or agora event and
     return an ack;
   - queries (later: `recall`, `consult`, ...) return data, appended as `tool`
     role messages for a follow-up turn.
6. **Fold.** Soul events update the cached `#soul{}`. Bump the token counter.
7. **Threshold check.** If the Chronicle window exceeds the token budget, mark it
   for the sleep cycle (a no-op stub in Phase 1: just trim the window).
8. **Idle.** Return to `{noreply, State}` and cost nothing until the next trigger.

Steps 4 and 6 are why the spinoza crash class is gone: a thought becomes an event
appended to a log, not a mutation flushed to a file that can tear.

## Deliverable and proof

A mind that:

- boots, replays its Soul stream, and knows its name, charter, and lessons;
- amends its own charter via `amend_charter`, restarts, and still holds the
  amendment (identity survives the process);
- carries grand strategy and working memory across turns and restarts;
- shows a coherent HUD;
- speaks only when it has something to say (Phase 0 behavior preserved).

The test that matters: amend the charter, kill the gen_server, let the supervisor
restart it, and confirm the amendment is present in the next assembled L2. That is
the decoupled-identity claim made concrete: the Soul outlives any single run of
the suit.
