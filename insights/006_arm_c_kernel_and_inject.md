# 006 — Arm C: the kernel contestant, its `inject`, and the first result

**Status:** implemented and run (`hecate-arena`, arm C = `arena_kernel`). First
kill-criterion result is in, and it is a **pre-registered FAIL on the pilot
world** — an honest finding, recorded here rather than tuned away.

## ELI5

The real student (C) has the alarm (notices change), the notebook (remembers past
rules), *and* a small learner that fits the current rule. When the alarm fires and
the notebook recognises the situation, it doesn't hand the learner a finished
answer — it **shows the learner a few worked examples from last time and lets it
practise on them** (that is the honest "inject"). Then the learner predicts.

We tested it. On this particular quiz — where the numbers are clean and the same
rules come back almost identically — the plain **notebook-only** student (E) is
just better: looking up the nearest past answer beats re-learning, every time. So
on *this* quiz the fancy student does not earn its keep. That is a real result. We
write it down and design a *harder* quiz (noisier, patterns that return only
roughly) where a learner should beat a lookup — and we commit to that harder quiz
*before* running it, so we can't cheat by quiz-shopping.

## What `inject` actually is (corrected after Fable, round 6)

The draft said "warm-start the engine from stored parameters." Fable killed it,
correctly, and the correction is the important part of this note:

- **Storing engine weights is `snapshot`/`restore`, not `inject`.** Weights are
  θ-shaped: they do not survive an engine swap, so that arm can never demonstrate
  the Spartan claim (a self that persists across engines), and Experiment 2 is
  pre-broken. It would also conflate "engine at inference" with "consolidation at
  storage", so a C-over-E win could not be attributed.
- **The honest inject:** memory stores **canonical exemplars** — `{window,
  outcome}` pairs, engine-independent and portable, the kernel never touching θ.
  This is the *same payload arm E stores*. On a match, C **replays** the matched
  exemplars through the engine's own online update (a few-shot refit); E averages
  them (raw lookup). Same payload, different use, so C-vs-E isolates the engine's
  contribution, and LLM-vs-net stays fair later (both get exemplars, not weights).

Also corrected (Fable r3/r6): the pilot engine is an online **linear** predictor,
and a linear map over the lag window **is** the AR generator's model class. So on
this world a C-win would be suspect regardless; we expected a loss and got one.

## The pieces (004, realised)

- **Detector** (= arm D): EWMA of surprise; a spike means "regime changed".
- **Canonical memory**: `{window, outcome}` exemplars, keyed by the raw recent
  window (004 option 1; a learned encoder is deferred to richer sensors).
- **Engine** (swappable): online NLMS linear predictor.
- **inject = replay**: on a shift, if the fresh window matches stored exemplars,
  replay the K nearest through the engine's update; no match → learn cold, like D.

## First result (pilot world, seeds 1..12)

| arm | regret | recovery (τ) | asym median |
|---|---|---|---|
| e_memory | 2.01 | **25.8** | **0.082** |
| c_kernel | **1.57** | 46.8 | 0.099 |

C beats E on aggregate **regret** (−0.44) but does **not** match E's recurrence
recovery and does **not** beat D there (`recovery_c_minus_d` ≈ −1.3, variance
~927 — no reliable difference). **Per the primary kill criterion (recovery vs
D/E), the kernel does not earn its keep on this world.**

This is a finding, not a bug (Fable r6 #4): on a dense, low-noise, linear stream,
raw k-NN is near-perfect — "k-NN heaven" — and a learning engine cannot catch
lookup on recovery speed. The engine earns its keep only where coverage is thin
and noise is high, so lookup degrades and a model must interpolate.

## Experiment 1b — pre-registered BEFORE it runs

The disciplined response (not world-shopping): keep this result, and pre-register a
harder world where the engine *should* win, then run it.

- **Sparser / harder world:** higher noise, shorter regime visits (thin exemplar
  coverage), **perturbed recurrence** (regimes return with jittered parameters,
  not near-identical windows), and at least one **deceptive near-match** to punish
  over-eager retrieval. A learned encoder (004 option 2) may be needed for the key.
- **Pre-register the match threshold** on separate seeds; **report the match-quality
  distribution** so a reviewer can see C's wins do not ride on trivially perfect
  keys.
- **Hypothesis:** in the sparse world E (lookup) degrades faster than C (model), so
  C beats E on recovery and asymptotic error. If C still fails, the kernel is dead
  weight even where it should shine — a stronger, more important negative result.

## The remaining open thing (Fable r6 #5)

The silent invalidator was the θ-shaped payload; it is fixed (exemplars, not
weights), so a future C-win would actually mean the contract works and would port
to the net engine. The other watch item: an online *linear* engine on an AR world
is nearly optimal, so any C-win on a linear world must be discounted — Experiment
1b's world should be nonlinear enough that the engine genuinely approximates.
