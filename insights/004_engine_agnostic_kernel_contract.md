# 004 — The engine-agnostic kernel contract

**Status:** hardened after Fable's red-team (round 4). Buildable, with four fixes
folded in and one that reaches back and changes the experiment ([003](003_metric_and_kill_threshold.md)):
a new **arm E**. Still the blocker for Experiment 1, but now honest about what it
does and does not claim.

## ELI5

A "mind" here has two parts: the **brain** (the engine — a language model or an
evolved net) and the **self** (the kernel — its memory, habits, name). We want the
self to run on either brain and survive a brain swap, so we describe what the self
*does* without assuming it thinks in words.

The brain must offer a few primitives (turn input into a *fingerprint*, make a
guess with a *confidence*, say *how wrong* it was, and take looked-up notes back
in). The self adds a **notebook**, an **alarm** for sudden wrongness, some
**adjustable habits**, and the ability to **distil many notes into a few rules of
thumb**.

Two honest catches this round: (1) writing your own *story* about who you are needs
language, so a wordless brain can't do it (that's why the plan keeps a language
model as narrator). (2) A notebook you look things up in is *already a predictor by
itself* (look up the nearest past situation, copy what happened). So we have to
prove the brain-plus-notebook beats the **notebook alone** — otherwise we've just
shown a filing cabinet works, not that we built a mind.

## The stance: sort faculties, don't pretend they all port

The kernel today is prompt-shaped. The honest move is to sort each faculty into
portable or language-bound, and design only the portable ones as engine-agnostic.

| Faculty | Portable? | Note |
|---|---|---|
| Perception **slot** | yes | the *slot* ports; the representation inside it does not (see boundary) |
| Episodic memory | yes | a similarity store over a canonical key space |
| **Memory consolidation** (episodes → prototypes) | yes | distilling regime prototypes from traces is pure statistics; only the *linguistic* library is bound |
| Self-audit (monitor + gate) | yes, but | reduces to change-point detection at this task scale (see honesty note) |
| Policy adaptation | yes | a small parameter set the mind tunes |
| Memory-transfer value across swap | yes | behavioural, not definitional (renamed from "continuity") |
| **Narrative self-authorship** | no | editing a *linguistic* self-model needs language |
| Linguistic knowledge library / reflection / drones | no | text reasoning |

The bottom rows are the argument for the **hybrid**: numeric engine gets the
portable faculties, an LLM reflector supplies the language-bound ones. And say the
size out loud: **the portable Spartan is a memory store, a change detector, a
consolidation step, and a dozen tuned scalars.** Small and falsifiable, not grand.

## The engine interface (all the kernel can see)

- `perceive(observation) -> repr` — the engine's private representation (LLM
  embedding; net activations). Used only as an optional retrieval re-rank, never as
  the memory key.
- `act(context) -> (action, uncertainty)` — prediction + self-reported uncertainty.
- `surprise(prediction, outcome) -> scalar` — error signal.
- `inject(context, traces) -> context'` — the channel by which retrieved memory
  enters the next act. **This is not free (see the asymmetry below).**
- `params` — opaque θ; `snapshot()`/`restore()`, and `vary()`/`select()` for
  evolvable engines. The kernel never reads θ.

## The kernel faculties

**Memory.** Store of `(key, context, action, outcome, surprise)`. The **key is in a
kernel-owned, engine-independent space**, with three named options in ascending
richness:
1. **raw observation features** — trivially portable; sufficient for the low-dim
   synthetic stream of Experiment 1.
2. **kernel-owned learned encoder** — a small autoencoder/contrastive encoder
   trained on the mind's *own* observation history. Engine-independent (the kernel
   owns it, it survives swaps) yet learned (needed for any rich observation space).
   **This is the pre-registered answer for anything past the toy stream**, and the
   fix for the false dichotomy the draft had (raw features vs the engine's repr).
3. the engine's private `repr` — richest, non-portable; used only as a recomputed
   re-rank at retrieval time.

Retrieval = k-NN in the canonical key space (option 1 or 2), optional re-rank by
option 3. A gating policy decides store/forget. Retrieved traces enter the next act
via `engine.inject`.

**Self-audit (monitor + gate).** Consumes `surprise` trend + `uncertainty` +
engine-vs-memory disagreement, emits {accept, defer, adapt, flag}. **Honesty note:
at Experiment 1's scale this reduces to change-point detection (CUSUM with extra
inputs).** That is fine, arm D is an honest control precisely because of it, but a
C-over-D result is *not* evidence for "self-audit" in the rich sense. Self-audit
only becomes more than detection when its output *drives* something: gating
consolidation, spending the policy budget, or (in the hybrid) triggering linguistic
reflection.

**Policy adaptation.** A small parameter set (retrieval threshold, forget rate,
gate thresholds, goal weights) the mind tunes from its own performance. Called
*adaptation*, not authorship, on purpose.

**Memory-transfer value across an engine swap** (renamed from "continuity").
Continuity-as-defined was circular: the self survives a swap *because we put it
outside θ*. The non-tautological, measurable quantity is behavioural: **new engine
+ old memory vs new engine + fresh memory, same task.** If the old memory helps the
new engine, the self transferred something real. "Identity" is otherwise just a
label on a key-value store and does no work; drop the grand word, keep the number.

## The representation boundary (the load-bearing call)

The kernel owns the canonical key space; the engine owns its private `repr`. The
draft framed this as raw-features vs engine-repr, which was a false dichotomy: the
**kernel-owned learned encoder** (option 2 above) is engine-independent *and*
learned. For Experiment 1 (low-dim, regime identity recoverable from raw
statistics) raw keys are fine and do not gut C-vs-D. The death-on-arrival risk is
*deferred, not absent*: it returns with any rich observation space, and the
kernel-owned encoder is the pre-committed answer.

## The `inject` asymmetry (the deepest finding of this round)

Bolting memory onto a net's input is **not** free. Concatenating retrieved trace
vectors only helps if the net was trained/evolved *with that channel populated*;
otherwise it ignores the channel (zero weights) or degrades. Every real
memory-augmented architecture (DNC, retrieval-augmented RL, fast-weights) trained
memory end-to-end. **The competence to exploit `inject` is itself a learned
faculty: LLMs get it for free from pretraining (in-context learning); nets must be
evolved to possess it.**

Consequences, stated as limitations rather than discovered later:
- The *interface* is engine-agnostic; the engine's *competence* to use it is not.
- Phase-2 evolution must evolve the net **in the presence of the kernel** (kernel
  and engine are not cleanly separable). Experiment 2's engine-swap will otherwise
  "fail" for a reason the contract pretended away.
- Expect a **coevolution moving target**: the inject channel's statistics depend on
  the store, which depends on gating policies being tuned concurrently. Plan for
  the instability; do not be surprised by it.

## Ties to the experiment (003), including a new arm

- Arm **D** (detector-only) = self-audit monitor, empty store.
- Arm **C** (kernel-on) = D + episodic memory + inject.
- Arm **E** (memory-only) = the retrieval store used **directly as a predictor,
  engine bypassed** (k-NN over the canonical keys, copy/interpolate the stored
  outcomes). **New this round, and non-negotiable.**

Why E is non-negotiable: k-NN over raw observation windows with outcomes attached
*is a nonparametric predictor* (locally-weighted regression in a kernel costume).
Without E, C could beat D purely because that side-predictor is good on
regime-recurrent data, with the engine and `inject` contributing nothing — and we
would announce "the kernel helps the engine" having actually shown "k-NN beats no
k-NN", a result from the 1970s. **The kernel claim survives only if C beats E *and*
D:** the engine must add value over its own memory, and the memory over the
detector. If C ≈ E, Experiment 1 tested a database, not a mind. (003 is updated to
carry arm E and this threshold.)

## Honest concessions (say them before Fable does)

- **Narrative self-authorship does not port.** The case for the hybrid.
- **"Continuity" was circular**; the honest quantity is memory-transfer value.
- **The memory-as-predictor confound** is real and is why arm E exists.
- **`inject` competence is a learned faculty**, free for LLMs, evolved for nets;
  engine and kernel are not cleanly separable.
- **Self-audit reduces to change-point detection** at this scale; do not cite
  C-over-D as evidence of rich self-audit.
- **Self-reported uncertainty is unreliable**; prefer ensemble/consistency signals.
- **Policy adaptation edges toward learning/selection**; not claimed as authorship.

## Open for Fable (next round)

1. Does arm E fully close the confound, or can C still "pass" by laundering the
   memory predictor through `inject` while the engine adds nothing?
2. Is the kernel-owned learned encoder itself a confound (it is trained on the same
   history the memory stores — double-dipping)?
3. Given the inject asymmetry, is Experiment 2 (LLM-vs-net swap) even well-posed, or
   must the net be co-evolved with the kernel first, making "swap" meaningless?
