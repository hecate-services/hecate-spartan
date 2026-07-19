# 009 — Experiment 1b-prime: fix the contestant, not the world (pre-registration)

**Status:** PRE-REGISTRATION, **CLEARED by Fable (round 9, two-pass), frozen BEFORE
building.** 1b (note 008) was a signed negative whose cause the arm-F control pinned
on the **engine**, not the kernel faculties. 008's directive: fix the CONTESTANT in
the SAME frozen hard world (falsification), never change the world after a loss
(shopping). Round 9 ran probes on the frozen world and killed the draft's match gate
(a rubber stamp that accepted 84% of attempts and silently disabled the reset),
demanded the win branch be made attributable (controls F′ and C_reset), caught a
bias-term hole in the reset, and caught scored-seed reuse. The confirmation pass
caught two more (the B re-seat looked backwards in time; the p25 gate had a bootstrap
circularity) — both fixed below, and Fable then cleared it with no re-review. Round 9
also RETRACTED its own r8 "high-frequency deficit" diagnosis: the rule bandwidth
γ=0.261 *improves* the engine; the world's optimal basis is smooth.

## ELI5

Last quiz our learning student lost, but we proved the learning *machinery* was fine
— the calculator was too weak and the "have I seen this?" rule guessed wrong half the
time. So we do NOT change the quiz. We give the SAME student fixes, all frozen now in
writing, and we make two promises we nearly broke: the "have I seen this?" rule must
be STRICT (only the closest quarter of matches count) or it rubber-stamps everything
and the other fixes never fire; and to prove a win came from *memory* and not just
from a wipe-the-scratchpad reflex, we add two stripped-down students to beat — the
calculator alone, and the calculator-with-reflex-but-no-notebook. If the full student
can't beat lookup even now, that is close to a final answer, and we say so.

## The world: UNCHANGED

`arena_world:hard_config()`, byte-identical to 1b, floor `noise·√(2/π) = 0.240`.
**Scored on FRESH seeds 13..24** (the r8/r9 diagnostics and the calibration below all
used 1..12; the contestant must not be scored on realizations whose statistics shaped
it). Seeds 1..12 reported as a secondary panel. Only arm C and its named controls
change; A/B/D/E are untouched.

## Calibration (all rule constants come from here, on SEPARATE seeds)

Calibration seeds = `900000+s` (the floor-estimation rollouts, disjoint from every
scored seed). A rule is honest iff its functional form was fixed before scored
results, it is computed on disjoint data, and it would have been the same rule had 1b
won. The three constants below are frozen as RULES; their numeric values are whatever
the calibration data yields.

- **Engine bandwidth** `γ = 1 / median_pairwise_window_distance` (median heuristic;
  fixed-seed subsample). Measured: median distance 3.832 → γ = 0.261.
- **Engine width** `D = 256` (a standard "enough features" count; the calibration
  grid is flat, D=64≈256≈1024 at rule γ, so D is cosmetic not a tune).
- **Match gate** = the pre-registered **p25 quantile of the kernel's nearest-exemplar
  attempt-distance distribution on calibration rollouts** (see fix 2). Rule-derived,
  not a hand-set threshold.

**Validity gate (pre-declared):** the bare rule-tuned engine F′ must reach asymptotic
error ≤ 1.15× floor on calibration, else the world cannot adjudicate the architecture
claim and the run is void. Measured: F′ asym = 1.05× floor — passes.

## The frozen fixes (arm C only)

### Fix 1 — a competent engine, tuned by a rule not by the result

RFF engine with `γ` from the median heuristic and `D = 256`, both from calibration
(above). NLMS step unchanged (0.3). Measured effect: bare-engine seg-regret
0.155 → 0.118, asym 1.05× floor. D∈{64,1024} and the rule-vs-fixed-γ contrast are
**labeled exploratory**, never re-picked after seeing C's score.

### Fix 2 — a STRICT, rule-derived, freeze-on-alarm match gate

The draft's `κ·σ̂·√(2M)` gate was a rubber stamp: at 1.5·0.24·√10 ≈ 1.14 it accepted
84% of attempts (above the p75 of the measured nearest-distance distribution:
p50 0.487, p75 0.849, p90 1.446), so it *lowered* precision below 1b's 47.5% and left
the reset (fix 3) reachable on only 16%. Replaced:

- **Gate = calibration p25 quantile** of the kernel's nearest-exemplar attempt
  distances (accept only the closest quarter of matches). Rule-derived; kills `κ` as a
  free parameter; lands near 0.35–0.5 by construction.
- **The p25 is measured by a SHADOW RUN, to cut the bootstrap circularity** (the
  attempt distribution otherwise depends on the gate, since replay/reset perturb the
  engine → alarms → attempts). The shadow run is the kernel on calibration rollouts
  with **replay AND reset disabled** (detector + store active, both interventions
  no-op'd); its nearest-exemplar attempt distances give the p25. **That numeric
  threshold is pinned into this document as a frozen constant BEFORE any scored seed
  runs** — the rule is frozen now, the value is mechanically determined at build time,
  never chosen.
- **Precision guard:** additionally require the K nearest exemplars mutually within the
  same gate (tight cluster), else reject as ambiguous — this is what refuses the
  deceptive/poison clusters. (Watch-item, not a knob: closest-quarter + the guard may
  push effective inject recall below 25%; no recall knob is added — the firing counts +
  the precision diagnostic make a starved-inject outcome visible and correctly
  attributable, which is the difference from 1b.)
- **σ̂ is dropped from the gate entirely** (so the post-shift-inflation failure mode
  Fable flagged cannot arise). No residual-scale term survives in the gate.

### Fix 3 — detector reset on a novel shock, INCLUDING the level

On an alarm with NO accepted match: **decay the engine weights W by ρ = 0.5 AND
re-seat the bias B to the running mean of observations SINCE the alarm, updated
across the reacquire window** (D's restart semantics). The alarm-time "last L values"
are mostly PRE-shift (old regime), so anchoring B to them re-seats the level to the
regime just left and B then crawls off that wrong anchor at LR 0.05 — the exact
bottleneck this fix exists to remove; B must track post-alarm observations only. B
carries the regime level and learns slowest, so decaying W while leaving B stale
would miss what D's hard reset clears. On an alarm WITH an accepted match: replay, no
decay. ρ pre-registered; ρ sensitivity is one-pass exploratory.

### Measurement (referee, offline) — inject provenance

Arm C logs per replay the storage-step of each replayed exemplar; the referee joins
against the world's `step_regime` offline to report **inject precision**. The kernel
never reads `step_regime`. Precision is **diagnostic only** — it is never a
run-validity gate nor a selection input (that would select runs via ground truth).

## The confirmatory roster (both outcome branches must attribute)

Fixing the loss branch is not enough; a WIN must attribute to memory, not to a
transplanted reset. So two controls are **confirmatory, not exploratory**:

- **F′** — the bare rule-tuned engine (fix 1 only). Isolates faculties vs engine.
- **C_reset** — **C with the exemplar store disabled**: with no store there are no
  matches, every alarm takes the reset path, and the code path is mechanically
  identical to C minus only the store (killing implementation-difference confounds).
  Isolates whether memory adds over a transplanted detector-reset.
- **C** — the full contestant (fixes 1+2+3 + memory/inject).

Run against the unchanged D and E, all paired per seed. (One labeled-exploratory
arm: a **match-gated no-op** — on match do nothing, on no-match reset — to isolate
replay from reset-withholding. Exploratory, not a confirmatory criterion; the kill
surface stays frozen.)

## Kill criterion (unchanged core, attribution added)

- **Primary:** C beats E on bounded per-segment regret AND on recurrence recovery;
  C recovers **≥ 2× faster than D** (≤ ~18.6 steps vs D's ~37).
- **Memory attribution (new, confirmatory):** C beats **C_reset** on recurrence
  recovery — else a C win is the reset (a transplanted D faculty), not the kernel's
  memory/inject. The bar is not self-fulfilling: measured F′ recovers ~37–40 like D,
  so 2×-vs-D genuinely requires memory to work.
- The **asymptotic co-primary is pre-declared NON-ADJUDICABLE in this world** (E sits
  at 1.03× floor — no headroom); seg-regret + recovery carry the verdict.
- F′ and inject precision reported every run.

## Hypothesis and falsification

**Hypothesis:** with a rule-tuned engine, a strict rule-derived precision gate (so
inject precision rises well above 52%), and a level-including reset, C beats E on
seg-regret and recovery, and beats C_reset on recovery. Headroom is thin but real:
F′ seg-regret 0.118 vs E 0.098, so the faculties must contribute ≥ 0.020 (they
contributed 0.008 in 1b through a coin-flip gate; a precise gate has room to earn it).
**Falsified if** the full contestant still fails to beat E: a near-final negative for
this problem class — nonparametric lookup dominates a parametric-engine-plus-replay
learner in cheap-data, locally-smooth, non-stationary prediction. The response is NOT
a fourth same-world fix; it is 1c (extrapolation, only under 008's strict conditions:
1b/1b-prime signed first, E upgraded to LWLR, asymmetric pre-registration, last world)
or accepting the thesis is falsified for numerical prediction.

## Anti-Goodhart guards (frozen here, before the run)

- Every constant (γ-rule, D=256, gate=calibration-p25, ρ=0.5, L, K, warmup) is frozen
  now; the gate and bandwidth are RULES on disjoint calibration seeds, not hand-set.
- **Primary scored on fresh seeds 13..24**, disjoint from all calibration and all
  diagnostic seeds; 1..12 secondary.
- ONE confirmatory run. A loss is signed, not re-tuned. The world is UNCHANGED.
- This is the last same-world fix; if C loses, the next move is 1c-or-stop, never
  1b-double-prime.
