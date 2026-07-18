# 004 — The engine-agnostic kernel contract

**Status:** DRAFT, going to Fable for red-team. This is the blocker for
Experiment 1 ([003](003_metric_and_kill_threshold.md)): the kernel cannot be
tested against a non-linguistic engine until we say what "memory", "self-audit",
"self-authorship" and "continuity" mean when there are no words.

## ELI5

A "mind" here has two parts: the **brain** (the engine — maybe a language model,
maybe an evolved neural net) and the **self** (the kernel — its memory, its
habits, its name). We want the self to run on *either* kind of brain, and to
survive when you swap the brain out. So we have to describe what the self *does*
without assuming it thinks in words.

This note pins down the small set of things any brain must offer the self (roughly:
turn what it senses into a *fingerprint*, make a guess with a *confidence*, and
report *how wrong* it was), and what the self builds on top: a **notebook** of
fingerprints it can look up, an **alarm** for when it is suddenly wrong, a set of
**adjustable habits**, and a **name** that stays the same when the brain is
replaced.

It is also honest about one thing that probably *cannot* be carried to a wordless
brain: **writing your own story about who you are.** That needs language. Which is
exactly why the long-term plan keeps a language model around as the "narrator" even
when an evolved net does the fast thinking.

## The stance: classify faculties, don't pretend they all port

The kernel today is prompt-shaped: memory is text in a prompt, self-audit is a
second text pass, self-authorship is editing a text Soul. The honest first move is
not to force all of that onto a net, but to **sort each faculty into portable or
language-bound**, and design only the portable ones as engine-agnostic.

| Faculty | Portable to any engine? | Why |
|---|---|---|
| Perception / representation | yes (with a boundary, below) | every engine maps input to some internal vector |
| Episodic memory | yes | a similarity store over a canonical key space |
| Self-audit (monitor + gate) | yes | built on scalar surprise/confidence, not words |
| Policy adaptation | yes | a small parameter set the mind tunes |
| Continuity across engine swap | yes (by construction) | the self lives outside the engine's weights |
| **Narrative self-authorship** | **no** | editing a *linguistic* self-model needs language |
| Two-tier knowledge library | no | linguistic retrieval + summarisation |
| Linguistic reflection / drones | no | text reasoning |

The bottom rows are not failures; they are the argument for the **hybrid**: the
numeric engine gets the portable faculties, and an LLM "reflector" supplies the
language-bound ones. The contract is honest that a bare numeric mind cannot author
a narrative self, and that "my topology evolved" is selection acting on the mind,
not the mind authoring itself.

## The engine interface (what any engine must implement)

The kernel talks to the engine only through these. Nothing else about the engine
is visible to the kernel.

- `perceive(observation) -> repr` — map an observation to the engine's own
  representation vector. (LLM: an embedding. Net: hidden-layer activations.) Used
  as an *optional* retrieval re-rank signal, never as the primary memory key (see
  the representation boundary).
- `act(context) -> (action, uncertainty)` — produce the prediction/action plus a
  self-reported uncertainty. (LLM: token logprobs / ensemble spread. Net: output
  distribution / ensemble variance.)
- `surprise(prediction, outcome) -> scalar` — how wrong the last act was. The raw
  material of self-audit and shift detection.
- `inject(context, traces) -> context'` — the engine-specific channel by which
  retrieved memory enters the next act. (LLM: exemplars as prompt tokens. Net:
  retrieved trace vectors concatenated to the input, or used to modulate
  activations.) **This is the operation people forget exists**, and it is where the
  "what does memory mean to a net" question is actually answered.
- `params` — opaque weights θ, with `snapshot()` / `restore()`, and for an
  evolvable engine `vary()` / `select()`. The kernel treats θ as a black box it can
  save, reload, and (for nets) breed. It never reads θ.

## The kernel faculties, defined on that interface

**Memory.** A store of traces `(key, context, action, outcome, surprise)`. The
**key is in a canonical, engine-independent space** (raw observation features),
*not* the engine's `repr`. Retrieval = k-NN in canonical space, optionally
re-ranked by the current engine's `perceive`. A gating policy decides what to store
and what to forget. Retrieved traces enter the next act via `engine.inject`. This
is the faculty Experiment 1 tests: arm C = kernel with this store; arm D = kernel
with the store *empty* (monitor only).

**Self-audit (monitor + gate).** Consumes the `surprise` trend, `uncertainty`, and
the disagreement between the engine's action and the memory-implied action. Emits
one of {accept, defer, adapt, flag}. "Draft-then-verify" becomes: engine proposes,
kernel checks the proposal against these signals, then accepts / defers / triggers
adaptation. The shift-detector is exactly this monitor with memory switched off —
which is why it *is* arm D.

**Policy adaptation (the portable slice of "self-authorship").** A small parameter
set the mind owns and adjusts from its own performance review: retrieval threshold,
forget rate, gate thresholds, goal/priority weights. Deliberately called
*adaptation*, not authorship: the mind tuning its own knobs from experience is real
and portable, but it is not the same as narrating a self, and we will not dress it
up as such.

**Continuity across engine swap.** The self = {identity, memory, policies,
self-model}, and it lives **outside θ by construction**, so swapping the engine
preserves it. The hard part, and the reason the memory key is canonical: an old
engine's `repr` is meaningless to a new engine, so a memory indexed on engine
embeddings would be dead on swap. Canonical keys survive; the new engine's
`perceive` re-rank is simply recomputed. Measurable continuity (per 003) =
retention of behaviour/score across a mid-life swap.

## The representation boundary (the load-bearing design call)

Everything hinges on one line: **the kernel owns a canonical, engine-independent
representation (observation features); the engine owns its private `repr`.** Memory
keys, policies, and identity live in canonical space and port across engines. The
engine's learned `repr` is richer but non-portable, so it is used only as a
recomputed re-rank signal, never as the thing the self is stored in.

The tension is real and worth stating plainly: canonical keys throw away the
engine's learned similarity, which is often the best similarity. We accept that
cost to buy cross-engine continuity, and we let the engine's `repr` claw some of it
back at retrieval time. Whether that trade is worth it is itself measurable (memory
keyed canonical-only vs canonical+repr-rerank is an ablation).

## Engine realizations

| Contract op | LLM engine | Evolved-net engine |
|---|---|---|
| `perceive` | text embedding | hidden activations |
| `act` | decode; uncertainty from logprobs/ensemble | forward pass; uncertainty from ensemble variance |
| `surprise` | error vs outcome (or NLL) | prediction error |
| `inject` | retrieved exemplars as prompt tokens | retrieved trace vectors concatenated / modulating input |
| `params` snapshot/restore | checkpoint (frozen) | genome save; `vary`/`select` = evolution |
| narrative authorship | native (edits linguistic Soul) | absent — needs the LLM reflector (hybrid) |

## Ties to the experiment (003)

- Arm **D** (detector-only) = the self-audit monitor with an empty memory store.
- Arm **C** (kernel-on) = D plus the episodic memory faculty.
- So **C vs D is precisely a test of the memory faculty as defined here**, holding
  the monitor constant. Clean attribution, which was the whole point of adding D.
- **Continuity** = kernel state (canonical memory + policies + identity) survives an
  engine swap; Experiment 2's retention metric measures it directly.

## Honest concessions (say them before Fable does)

- **Narrative self-authorship does not port.** A bare numeric mind adapts policies;
  it does not author a self. This is a real limit and the case for the hybrid.
- **Canonical keys sacrifice the engine's best similarity** for portability. A
  bet, and an ablatable one.
- **Self-reported uncertainty is unreliable** (LLM verbalized confidence is poorly
  calibrated). Prefer ensemble/consistency signals over `uncertainty` where they
  disagree.
- **"Policy adaptation from performance" edges toward being learning/selection by
  another name.** We do not claim it is authorship; we claim it is portable and
  measurable, nothing more.

## Open for Fable

1. Is the portable/language-bound split honest, or am I quietly smuggling the hard
   parts into "language-bound" to make the rest look clean?
2. Is the canonical-vs-engine representation boundary the right call, or does it
   gut the memory faculty so badly that C-can-never-beat-D and the experiment is
   dead on arrival?
3. `inject` for a net (concatenate retrieved vectors / modulate activations) — is
   that a real mechanism or hand-waving? Does it make the net's input non-stationary
   in a way that breaks training/evolution?
4. Is there a faculty I have mis-sorted (something I called portable that secretly
   needs language, or vice versa)?
5. What is the one thing in this contract that, if wrong, silently invalidates
   Experiment 1?
