# 003 — The metric and the kill threshold (pre-registration)

**Status:** hardened after Fable's red-team (round 3). Still one step from frozen:
the seed count `N` is set by a pilot (below), and the run is blocked on the
engine-agnostic kernel contract (next note). Everything else is committed. The
point of this document is to write the number down *before* building anything, so
the programme cannot quietly become serial reframing.

## ELI5

A student takes a one-question quiz every minute: "what is the next number?" Now
and then the teacher secretly changes the hidden rule. We compare students on the
**same brain**:

- **No-notebook:** only sees the last few numbers.
- **Alarm-only:** no notebook, but notices when its guesses suddenly go wrong and
  wipes its assumptions to start fresh fast.
- **Notebook (the "kernel"):** keeps a notebook of rules it has seen before, and
  looks them up.

The trick: some rule-changes are ones the student has **seen before**. Only the
notebook student can say "ah, the Tuesday rule again" and be right immediately.
The alarm-only student recovers fast too, but has to relearn every time. So the
real test of the notebook is not "does it beat the no-notebook student" (too easy),
it is **"does it beat the alarm-only student on rules it has seen before."**

And we make the notebook *dangerous*: sometimes a new rule *looks* like an old one
but isn't, so a careless notebook confidently gives the wrong answer. A notebook
that is only ever free is not being tested.

If the notebook does not clearly win where it should, and stay safe where it is
tempted, we declare it **dead weight** and say so, instead of inventing a friendlier
quiz.

## What is being tested

Whether the **sovereign kernel** improves numerical prediction, and precisely
**which part** of it does. The kernel bundles three mechanisms, and a bare "does
the kernel help" test cannot attribute a win. So the arms below tease them apart.
The metric is **engine-agnostic** (predict-next-value, scored by error), so the
identical harness later swaps the engine (LLM vs evolved net) for Experiment 2.

## The task

A synthetic stream over a **finite set of hidden latent regimes**. Each step: the
agent predicts, then observes truth. Four change types, mixed in a fixed,
pre-registered proportion:

1. **Recurrence** — a *previously seen* regime returns, after a gap. This is the
   fingerprint test of episodic memory.
2. **Deceptive near-recurrence** — a *novel* regime that resembles a stored one but
   differs. A retrieval memory must sometimes pay for a false match; without this,
   memory is never punished and the task is rigged pro-kernel. (Fable, r3.)
3. **Abrupt shock** — a jump to a genuinely new regime.
4. **Drift** — parameters slide continuously to a new regime; a drift window is
   defined to *end at slide completion* (no stationary target mid-slide).

Hard pre-registration constraints (each closes a specific rigging):
- **Recurrence gap ≫ the longest context window** used by any arm (stated factor,
  ≥ 3×). Otherwise a long-window arm literally re-reads the prior occurrence and
  "memory" becomes context. The kernel's real claim is therefore explicit:
  *memory helps when regimes recur beyond the context horizon.*
- The **generator family is frozen before the retrieval key is chosen** (or
  whichever is designed second is frozen against the first). Otherwise the same
  hands tune regimes to be separable by exactly the statistic the key uses.
- Regimes long enough that the best control's recovery time is **≥ 20 steps**, or
  the recurrence criterion is void (τ = 3 vs 6 is quantization noise, not a 2×).

## The arms (identical engine, identical *pre-registered token budget* per step)

- **A. stateless-short** — short recent window, no cross-window state.
- **B. stateless-long** — long window (subject to the gap constraint above);
  controls for raw information/compute without kernel structure.
- **D. detector-only** — self-audit shift-detector + context reset on alarm, but
  **no episodic store**. This is the cheapest mechanism hiding inside the kernel,
  and it alone likely beats A and B after a shock. **This arm is the real
  baseline for the kernel.** (Added per Fable r3 — without it a pass is
  unattributable.)
- **C. kernel-on** — same engine + episodic similarity-retrieved memory + the D
  detector + carried state.

Attribution logic: C vs D isolates **episodic memory** (the thing left when you
subtract the detector). C/D vs A/B isolates **detection+adaptation** from raw
context. The kernel-as-designed earns its keep only if **C beats D**, not merely if
C beats A.

**Compute is pre-registered as exact token counts per arm.** With an LLM engine,
prompt length *is* compute; "same budget" is meaningless unless the injected
exemplars (C), the long window (B), and the short window (A) are fixed to stated
token counts. Whoever tunes prompt lengths otherwise tunes the result.

## The metrics

**PRIMARY — recurrence recovery, C vs D.** On 2nd+ occurrences of a regime,
recovery time `τ` = steps until rolling error returns within `(1+δ)` of the
regime's achievable error and holds for `H` steps. Compared **C vs D** (not vs the
stateless arms): this is the only clean fingerprint of episodic memory, because it
subtracts out the detection skill D already has. Report the **step difference**
`τ(D) − τ(C)` alongside the ratio.

**SECONDARY — transient regret.** `R = Σ (e_t − e*_r)` over a post-shift window,
`e*_r` the achievable error for regime `r`. Binding statistic is the **paired
absolute difference** across seeds (Wilcoxon), not the ratio (ratios of small
error-differences are unstable). The ratio is reported for interpretability only.
`e*_r` is estimated by a **genie predictor given regime identity, fit on separate
rollouts of the generator, never on the scored realization** — so it cannot leak
into or flatter any arm (it cancels in paired comparisons regardless).

**PLACEBO (negative control).** On *first* occurrences of novel regimes, C must
show **no** significant advantage over D. If it does, either the scorer leaks or
the "memory" is acting as a generic regularizer, and the episodic-memory
interpretation is dead. Free, and the draft lacked it.

**GUARDS.** Asymptotic error `e∞` for C ≤ 1.05× best control on **both the median
and the 95th percentile**. The p95 guard catches the deceptive-near-recurrence
blowups a median hides (a memory that is fast on average but occasionally
catastrophically wrong on a false match is not safe).

**VALIDITY FLOOR.** All engine arms must beat a naive persistence/MA baseline, or
the task is trivial and the run is void (validates the *task*, not the kernel).

## Statistical protocol (frozen before any scored run)

- **Power, honestly.** N=24 was a guess dressed as a calculation. Instead:
  **pilot the control arms only (A, B, D)** to estimate the paired-difference
  variance, then fix `N` for the C-vs-D primary at 80% power for the threshold
  effect. No hypothesis arm (C) is touched during the pilot.
- **Superiority margin.** "CI excludes a <10% effect" is a superiority-margin test:
  we are powering to distinguish a 20% effect from a 10% one, which needs far more
  data than powering against zero. The pilot sizes for this explicitly.
- Comparing C against the **post-hoc best of the controls** is a conservative bias
  *against* C. Accepted, and stated.
- Paired across seeds; change-type mix, windows, token budgets, `T, δ, H`, the
  `e*_r` reference, and `N` all fixed before the first scored run. Any change voids
  the registration and starts a fresh one. No peeking, no early stop.

## The kill threshold (pre-registered)

The kernel **passes** only if ALL hold, else it is **dead weight on numerical
prediction**:

1. **Recurrence (primary):** `τ(C) ≤ 0.5 · τ(D)` on 2nd+ occurrences — at least
   **2× faster than the detector-only arm** — with the step difference above the
   20-step floor and significant. *This is load-bearing: no memory advantage over a
   plain shift-detector means the episodic store is inert.*
2. **Placebo:** no significant C-over-D advantage on first occurrences of novel
   regimes.
3. **Regret (supporting):** paired absolute transient-regret difference `R̄(C) <
   R̄(best of A,B,D)`, significant (Wilcoxon), effect consistent with ≥20%.
4. **Guards:** `e∞(C) ≤ 1.05 ×` best control on **both** median and p95.

**Why these.** 2× on recurrence-vs-detector is deliberately strong: recognising a
regime you have literally stored is the *easiest* thing a memory can do, so a weak
effect there is damning. The placebo and the p95 guard make "faster" mean "faster
*and* honest", not "confidently wrong sometimes". 5% steady-state guard stops a
"fast but worse" false win.

**On failure:** the finding is "the kernel is dead weight on stationary-ish
numerical prediction" — a real result. The response is to **park the kernel or
redesign the engine-agnostic contract** (what should "memory" and "self-audit"
even mean to a non-linguistic engine?), **not** to invent a task that lets it win.

## What Fable's red-team changed (round 3)

Added arm **D** (attribution); made **recurrence-vs-D the primary** metric; added
**deceptive near-recurrence** so memory can be punished; added the **placebo**
negative control and the **p95 guard**; fixed `e*_r` (genie on separate rollouts,
paired-difference binding, drift windows end at slide completion); replaced the
N=24 guess with **pilot-then-power**; pre-registered **exact token budgets** and
**generator-frozen-before-key**; made explicit that the kernel's claim is *memory
beyond the context horizon*.

## Still open (next steps)

- The **engine-agnostic kernel contract** must exist before this runs (what is
  "memory"/"self-audit"/"authorship" for a non-linguistic engine). That is the
  real engineering research and the next note.
- Run the **pilot** (A,B,D only) to fix `N` and the achievable-error references.
- Define measurable **continuity across an engine swap** before Experiment 2, or it
  is unfalsifiable.
