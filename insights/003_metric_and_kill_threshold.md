# 003 — The metric and the kill threshold (pre-registration)

**Status:** pre-registration DRAFT, under adversarial review by Fable. Numbers here
are committed-but-provisional: they get frozen only after the red-team pass. The
point of this document is to write the number down *before* building anything, so
the programme cannot quietly become serial reframing.

## ELI5

Imagine a student taking a one-question quiz every minute: "what is the next
number?" Now and then the teacher secretly changes the hidden rule that makes the
numbers. We compare two students on the **same brain**:

- **No-notebook student:** only remembers the last few numbers.
- **Notebook student (the "kernel"):** keeps a notebook of patterns it has seen
  before, notices when its guesses suddenly go wrong, and looks things up.

The key trick: some rule-changes are ones the student has **seen before**. The
notebook student should recognise it ("ah, the Tuesday pattern again") and snap
back almost instantly, while the no-notebook student has to relearn from scratch.

We measure **how many guesses each needs to get accurate again after a change.**
If the notebook does not help by a clear margin, we conclude the notebook (the
Soul, the memory, the whole Spartan kernel) is **dead weight for this kind of
task**, and we say so out loud instead of inventing a new task to save it.

That "clear margin", written down in advance, is the kill threshold.

## What is being tested

Whether the **sovereign kernel** (persistent memory + shift-detection self-audit +
carried self-state) measurably improves behaviour on a numerical prediction task,
and specifically **whether it recovers faster after the world changes.** The
kernel's whole promise only pays off under change; on a stationary task it is
expected to be dead weight, so the task is built around change.

The metric is **engine-agnostic** (predict-next-value, scored by error), so the
identical harness later swaps the engine (LLM vs evolved net) for Experiment 2.

## The task

A synthetic stream with a **finite set of latent regimes** the agent never sees
directly. Each step: the agent predicts the next value(s), then observes the truth.
The generator moves between regimes by three change types, mixed in known
proportions:

1. **Recurrence** — a *previously seen* regime returns. (The sharpest test of
   memory: a notebook should win big here.)
2. **Abrupt shock** — an instant jump to a *new* regime.
3. **Drift** — parameters slide continuously to a new regime.

Changepoints are hidden from the agent, known to the scorer. Regimes must be
non-trivial: a naive predictor (persistence + moving-average) must do *poorly*, or
the task is degenerate and proves nothing (see the validity floor).

## The arms (identical engine, identical per-step compute budget)

- **A. stateless-short** — engine sees a short recent window; no state across it.
- **B. stateless-long** — engine sees a *long* window. This is the control that
  matters: it matches the kernel's *information/compute* without the kernel's
  *structure*. It answers "is the kernel just a fancy way of saying more context?"
- **C. kernel-on** — same engine + the kernel: similarity-retrieved episodic
  memory, a self-audit shift signal (rising error triggers adapt), carried state.

The kernel only counts as real if **C beats the better of A and B.** Beating only
A means the kernel is just extra context, which is a kill.

## The metrics

**Primary — transient regret `R`.** For each changepoint into regime `r`, over a
post-shift window of `T` steps, `R = Σ (e_t − e*_r)`, where `e_t` is the agent's
per-step error and `e*_r` is the *achievable* error for regime `r` (estimated from
a reference predictor fully adapted to `r`). `R` is the excess error paid while
adapting: it bundles **speed and quality** into one number, lower is better.
Aggregate `R̄` over all changepoints and seeds.

**Sharpest sub-metric — recurrence recovery.** Restricted to *recurring* regimes
(2nd+ occurrence): recovery time `τ` = steps until rolling error returns within
`(1+δ)` of `e*_r` and stays for `H` steps. This is the tightest falsification of
"the memory does something": on a regime it has *already seen*, the kernel must
recover much faster than a stateless arm that must relearn. If it does not, the
memory is not working.

**Guard — asymptotic error `e∞`.** Median late-regime error per arm. Prevents a
false win: recovering fast *to a worse steady state* is not a win.

**Validity floor.** A naive persistence/MA baseline. All engine arms must beat it,
else the task is trivial and the run is void (this validates the *task*, not the
kernel).

## Statistical protocol (frozen before any run)

- **Seeds:** N = 24 independent generator seeds (proposed; sized for ~80% power to
  detect the threshold effect at α = 0.05). Each seed: a fixed number of
  changepoints `M` with the change-type mix fixed in advance.
- **Test:** paired across seeds (same seeds for every arm). Report effect size +
  CI, not just p. Bootstrap CIs on `R̄` differences.
- **No peeking / no early stop.** Arms, windows, `T, δ, H`, `M`, the change-type
  mix, and the reference for `e*_r` are all fixed before the first scored run. Any
  change voids the pre-registration and starts a fresh one.

## The kill threshold (pre-registered)

The kernel **passes** only if ALL hold, else it is declared **dead weight on
numerical prediction**:

1. **Transient regret:** `R̄(C) ≤ 0.80 · R̄(best of A,B)` — at least a **20%**
   reduction versus the best stateless arm, difference significant with the CI
   excluding a <10% effect.
2. **Recurrence:** on recurring regimes, kernel recovery is at least **2×** faster
   (`τ(C) ≤ 0.5 · τ(best of A,B)`), significant. This is the load-bearing one: no
   recurrence advantage means the memory is inert.
3. **Guard:** `e∞(C) ≤ 1.05 · e∞(best of A,B)` — the kernel must not buy speed by
   sacrificing more than **5%** of steady-state accuracy.

**Why 20% / 2× / 5%.** 20% is the smallest regret gain worth the kernel's
operational cost (memory I/O, self-audit, latency); below it the kernel is not
worth carrying even if statistically detectable. 2× on recurrence is deliberately
strong: recognising a regime you have literally seen before is the *easiest* thing
a memory can do, so a weak effect there is damning. 5% is a tight guard so "faster
but worse" cannot masquerade as success.

**On failure:** the finding is "the kernel is dead weight on stationary-ish
numerical prediction" — a real, publishable result. The response is to **park the
kernel or redesign the engine-agnostic contract** (what should "memory" and
"self-audit" even mean to a non-linguistic engine?), **not** to invent a new task
that lets the kernel win.

## Dependencies and open calibration questions (for Fable)

- Experiment 1 cannot run until the **engine-agnostic kernel contract** exists
  (next note). This document defines only how it will be judged.
- Open for the red-team: are 20% / 2× / 5% right, or gameable? Is transient regret
  the honest primary, or does recurrence-recovery deserve to *be* the primary? Is
  N=24 enough power? Does `e*_r` (achievable-error reference) smuggle in a confound?
  Is there a trivial kernel-on strategy that passes the thresholds without the
  memory doing anything real?
