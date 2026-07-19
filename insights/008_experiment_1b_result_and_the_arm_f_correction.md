# 008 — Experiment 1b: the result, and the arm-F correction

**Status:** built and run (`hecate-arena`, hard world + RFF engine + arm F control).
The result is a **signed NEGATIVE**, but a *narrower* one than the primary run first
appeared to show. Fable's round-8 red-team caught that the pre-registered inference
rule ("C fails to beat E → the kernel faculties are dead weight") committed an
attribution error, and it built the missing control (arm F) to prove it. The
correction is the important part of this note.

## ELI5

The harder quiz is here: noisier numbers, curvy rules, rules that come back slightly
changed. We expected the *learning* student (C) to finally beat the *lookup* student
(E). C lost again. But before writing "the learning machinery is useless," Fable
made us add one more student, **F: C's engine with the memory and alarm ripped out**.
Now compare three:

- E (pure lookup) is best.
- F (engine alone) is worst of the three.
- C (engine **plus** the memory/alarm/replay) sits **reliably above its own engine F**.

So the honest sentence is *not* "the machinery is dead weight." It is: **C loses to
lookup because C's *engine* loses to lookup — and the memory/replay machinery
actually helps its engine a little, consistently.** The thing that failed 1b is the
choice of engine (a slow parametric learner) against a lookup table on cheap,
locally smooth data. That is a known fact about learning, not a verdict on the
Spartan faculties. We could only see this once F existed.

## The build (proper slices, not a config fork)

1b is genuinely a *different* world and a *different* engine, so it got real seams,
not `if hard` branches in a god-generator (that would have been a backward-compat
shim, pinning correctness to an exact RNG interleaving):

- **`arena_dynamics` behaviour** (`base_regime`, `deceptive_regime`, `step_mu`,
  `drift_mu`) with `_linear` (1a) and `_nonlinear` (1b, a family
  {sine, tanh, cubic, kink} drawn per regime). A generic `arena_stream` owns
  everything the two worlds share (schedule, recurrence gap, jitter, realize, mu).
  1a stayed **byte-identical** through the refactor (golden-hashed), because the
  linear callbacks fire in the same random order by construction — determinism is
  structural, not a guarded skip.
- **`arena_engine` behaviour** (`init`, `predict`, `update`) with `_linear` (NLMS
  over the lag window) and `_rff` (NLMS over pre-registered random Fourier
  features, frequencies from a fixed world-independent seed — insight 007's
  blindness test). `arena_kernel` (the faculties) is now generic over the engine —
  which is exactly the engine-agnostic contract of 004 and the seam Experiment 2's
  LLM-vs-net swap needs.

## Result (1b primary: hard nonlinear world, RFF engine, 12 paired seeds)

Genie floor `e* = 0.240` (`noise·√(2/π)`, noise 0.3).

| arm | regret | recov τ | recFrac | segReg | asymMed | asymP95 |
|---|---|---|---|---|---|---|
| a_short    | 4.81 | 33.8 | 1.00 | 0.119 | 0.254 | 0.843 |
| b_long     | 19.20 | 54.6 | 0.99 | 0.385 | 0.262 | 1.024 |
| d_detector | 5.71 | 37.2 | 0.99 | 0.157 | 0.258 | 0.990 |
| **e_memory** | 4.23 | 43.3 | 0.99 | **0.098** | **0.247** | **0.753** |
| f_bare (engine) | 6.83 | 47.2 | 0.98 | 0.155 | 0.263 | 0.840 |
| **c_kernel** | 6.21 | 42.6 | 0.99 | 0.147 | 0.264 | 0.834 |

Paired differences (positive = first arm worse; var ≈ 0 unless noted):

| comparison | mean | reading |
|---|---|---|
| `segreg_c_minus_e` | **+0.049** | C **reliably worse** than lookup (> seed noise) |
| `segreg_f_minus_e` | **+0.057** | the engine alone is the whole deficit |
| `segreg_c_minus_f` | **−0.008** | **the faculties beat their own engine, reliably** |
| `recovery_c_minus_f` | −4.55 (var 129) | C recovers faster than its bare engine |
| `recovery_c_minus_e` | −0.63 (var 229) | tie, swamped by recovery-time noise |
| `recovery_c_minus_d` | +5.49 (var 202) | C **slower** than a plain detector (confound — see below) |

**Decomposition (Fable r8):** the entire C-vs-E gap (+0.049) is the engine's gap
(F-vs-E = +0.057); the faculties claw back a small, near-zero-variance slice
(C-vs-F = −0.008 seg-regret, −4.6 recovery). The faculties are **not** dead weight
relative to their own engine.

## What the primary run does and does NOT license

**Signed (this stands regardless of anything downstream):**

> In the pre-registered hard world, architecture C (RFF-64 + NLMS + kernel
> faculties) loses to raw k-NN over the same exemplar store on the seg-regret
> co-primary (+0.049, > seed noise) and fails the 2×-vs-D recovery criterion. By the
> bare-engine control, the deficit is the **engine's** (F−E = +0.057); the kernel
> faculties add small reliable value over their own engine (C−F = −0.008 seg-regret,
> −4.6 recovery, paired, ≈0 variance) **despite** a match gate that injects 47.5%
> wrong-regime exemplars. The claim "kernel + generic parametric engine beats lookup
> in dense-coverage nonlinear worlds" is **dead**. The claim "detector / memory /
> inject faculties are worthless" is **NOT supported** — the run could not test it
> until arm F existed.

**NOT licensed:** "the kernel is dead weight." That sentence fails the F control.

## Three corrections folded in (Fable r8)

1. **Tripwire amendment.** The frozen `all_beat_naive` tripwire tripped (would void
   the run), but it quantified over deliberately-weak yardstick arms (only `b_long`
   loses to naive persistence). Re-scoped to the **adjudicating arms {D, E, C}**; on
   that scope the primary run **passes** (it mis-tripped in 1a too). Recorded as an
   amendment, not silently waved. Honest addendum: naive persistence beats C on the
   20-step transient regret (4.30 vs 6.21) — explicable (persistence is strong under
   high autocorrelation with an absolute-error window), but it belongs in the record.
2. **The asymptotic co-primary was uninformative.** E's steady-state error is 0.247,
   only 1.03× the floor — still k-NN heaven at steady state, no headroom for any arm
   to separate. New validity gate `e_adjudicates_asym` (E must sit > 1.1× floor) reads
   **false** here, so the negative rests on **seg-regret and recovery**, not asym.
3. **The match gate is a coin flip poisoning half the injects.** THRESH = 0.5 was
   calibrated at 1a's noise (0.1) and never noise-normalised; at noise 0.3 + jitter
   0.3 it bisects the same-regime distance distribution — only ~46% of recurrences
   get any replay and **47.5% of replayed exemplars are wrong-regime**. That C still
   beats F while eating that is the strongest surviving evidence **for** the inject
   faculty, and a noise-scaled matcher is a legitimate same-world kernel fix.

The `recFrac → 0.75` alarm in the `nonlinearity_only` ablation was also an engine
artifact: the bare engine F collapses to recFrac 0.77 in the same world (its
steady-state error sits above the recovery band), so no memory faculty could enter
the band. "C fails to recover" was really "the engine cannot."

## Ablations (engine held = RFF; labeled exploratory)

C beats E on **no** lever. seg-regret C−E: nonlinearity +0.042, noise +0.006,
jitter +0.002, coverage +0.004. The nonlinearity lever (meant to *help* C) is where
the engine is weakest (F−E +0.062), confirming the deficit is representational
(gamma 1.0 / D 64 puts under one usable feature at the high frequencies the sine
regimes need), not a tuning accident.

## Next: fix the contestant, NOT the world (1b-prime pre-registration)

007's directive on a C-loss is "question the kernel/inject design." So the next run
is the **same frozen hard world**, one amended confirmatory run, with the contestant
repaired:

- **Noise-scaled, precision-aware match gate** (the 47.5%-poison fix): threshold as a
  multiple of the running error scale, not an absolute 0.5.
- **Detector's canonical response on a novel shock:** alarm with no match → weight
  decay / temporary LR boost, so C stops paying a re-convergence tax that D (hard
  reset) and E (automatic locality) never pay (this un-confounds `recovery_c_minus_d`).
- **Arm F is now a permanent arm**, and inject provenance (fired / match-precision,
  scored offline by the referee from the world's `step_regime` — the kernel stays
  blind) is reported.

Changing the contestant and re-running the frozen world is falsification. Changing
the world after a loss is shopping.

**On a future extrapolation world (1c):** k-NN-mean cannot extrapolate by
construction (its output is a convex combination of stored outcomes), so a world
built to break E off-hull proves nothing about the kernel — it is the mirror of the
E-as-strawman killed in round 7. 1c is legitimate only if (a) 1b is signed first and
stands regardless of 1c; (b) E is upgraded to the strongest fair same-store
nonparametric contender off-hull (locally-weighted linear regression, not k-NN-mean);
(c) the pre-registration is asymmetric — a C loss ends the program, a C win
establishes only the boundary claim ("fitted engines earn their keep off-hull / under
scarcity"), never a general resurrection. And it is the **last** world.

## The one line

The kernel does not beat lookup, anywhere we have looked — but it beats *its own
engine*, everywhere, by a hair. Whether that hair can be grown into a real advantage
by fixing the engine and the matcher (1b-prime) is the next, and possibly final,
question.
