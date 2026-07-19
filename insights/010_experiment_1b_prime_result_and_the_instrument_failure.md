# 010 — Experiment 1b-prime: a first positive, and an instrument failure

**Status:** built to the frozen 009 spec (Fable-cleared r9) and run. Two sentences
are **signed**; a third — the memory verdict — is **NOT signable**, because the run
never tested the memory faculty: a units error in the precision guard reduced inject
to 2 firings in 23,040 scored steps. Fable's round-10 red-team caught this (and my
overclaim on one metric), and it co-owns the guard bug from r9. The disciplined
response is an instrument repair on a NO-DATA criterion — not a re-roll of a loss —
pre-registered below.

## ELI5

We gave the learning student a better calculator and a fast wipe-the-scratchpad
reflex, and made its "have I seen this?" rule strict. Result: with the better
calculator and the reflex, the student finally beat the lookup student on the main
score — the program's first win. But the win came from the calculator and the
reflex, not from the notebook: the "have I seen this?" rule was SO strict it fired
twice all day, so we learned nothing about whether the notebook helps. Worse, the
strictness was an accident — we set the rule's bar using the distance to the single
closest page, then applied that same tiny bar to "are five pages all near each
other," which in a noisy world they never are. So the notebook wasn't tested; it was
gagged. We do not get to declare the notebook useless on a day it never spoke. We fix
the gag (a change decided from practice papers, not from the score), and run once
more on fresh papers.

## The build

Everything in 009, on real seams: engine parameterised by `init/2` (γ, D) with
reset callbacks (`decay_weights`, `set_bias`); `arena_kernel` generic over a POLICY
map (gate, precision_guard, reset, store, replay, provenance) whose defaults
reproduce 1b byte-for-byte; `arena_calibrate` deriving both constants from disjoint
calibration seeds; `arena_pilot:run_prime/1` with arms F′, C_reset, C_prime and the
offline inject-precision join. 1a stayed golden-hashed identical and 1b (008)
reproduced exactly (c 0.1467 / e 0.0979 / f 0.1549) through the whole refactor.
24 tests, dialyzer clean.

**Pinned calibration constants** (deterministic output of `arena_calibrate` on seeds
`900000+s`, computed before scoring, no free choice): **γ = 0.2513** (median
heuristic), **gate p25 = 0.3252**. Validity gate PASSES: F′ calibration asym = 0.254
= 1.05× floor, so the world can adjudicate the architecture claim.

## Result (confirmatory, fresh seeds 13..24, floor 0.242)

| arm | regret | recov τ | segReg | asymMed |
|---|---|---|---|---|
| d_detector | 5.35 | 30.3 | 0.122 | 0.236 |
| e_memory | 3.64 | 36.0 | 0.082 | 0.243 |
| f_prime (tuned engine) | 4.26 | 32.8 | 0.087 | 0.240 |
| c_reset (engine+reset, NO memory) | 2.94 | 32.3 | **0.068** | 0.234 |
| c_prime (full kernel) | 2.94 | 32.3 | **0.068** | 0.234 |

Paired (positive = C worse): `segreg_c_minus_e` **−0.014** (var 0, reliable);
`recovery_c_minus_e` −3.64 (var 191, a tie); `recovery_c_minus_d` +1.99 (a tie, but
fails the 2× bar); `recovery_c_minus_reset` **0.000**; `segreg_c_minus_f` −0.019.
Inject: **2 firings, precision 0.2, 2 of 12 seeds**.

**c_prime is identical to c_reset** (to 4 dp, all metrics). Integrity check (Fable
r10): on the 2 seeds that did replay (17, 24) the c_prime and c_reset prediction
vectors differ in 1353 and 873 places — so inject is correctly wired and a firing
does propagate; the aggregate identity is genuine starvation (2 fires), not a
dropped-return bug.

## The corrected tally (Fable r10 — I had overclaimed)

| criterion (009) | verdict |
|---|---|
| C beats E on **seg-regret** | **MET** (0.068 vs 0.082, reliable) — the program's **first C-over-E win** |
| C beats E on **recovery** | **TIE** (−3.64 vs sd 13.8 — does not separate; I wrongly called this MET) |
| C **≥ 2× faster than D** | **FAILED** (32.3 vs 30.3; the bar was ≤ ~15) |
| **memory attribution** (C beats C_reset) | **UNTESTED** — instrument failure |

## The two signed sentences

1. *1b-prime confirmatory (frozen world, fresh seeds 13..24): a rule-calibrated RFF
   engine with a detector-triggered reset beats raw k-NN over identical experience on
   segment regret (0.068 vs 0.082, paired, above seed noise) — the program's first
   C-over-E result; recovery vs E is a statistical tie; the 2×-vs-D recovery criterion
   failed. Attribution: engine competence and the reset (D's transplanted faculty),
   **not memory**.*
2. *The memory/inject faculty went untested in 1b-prime: the precision guard applied a
   nearest-distance quantile (0.325) to the K-nearest mutual-spread statistic whose
   same-regime scale is ~0.95, reducing inject to 2 firings in 23,040 steps. Instrument
   failure, recorded as such; no inference about the kernel thesis is licensed by this
   run.*

## The instrument failure, precisely

The precision guard requires the K=5 nearest exemplars to be mutually within the match
gate (0.3252). But 0.3252 is a quantile of the *nearest-neighbour distance* d₁; the
*mutual spread among 5 neighbours* has a same-regime null scale of ~noise·√(2M) ≈ 0.95
— roughly 3× larger. Requiring five noisy same-regime windows to sit inside a d₁-scale
ball is a category (units) mistake; the measured signature is the 473→2 collapse
(distance-gate-p25 alone fires 473 replays; adding the guard drops it to 2). It
entered 009's draft at gate 1.14 (mild); when the r9 mandatory change dropped the gate
to 0.33 the guard silently inherited a constant 3× too small for its statistic — a
miss we both made and neither caught until the faculty went silent.

## Why the ONLY inject evidence so far is *positive*

The one run where inject actually operated — 1b, at a coin-flip 47.5% match precision
— it was net **positive** over its own engine (`C−F` = −0.008 seg-regret, reliable,
note 008). 1b-prime adds **zero bits** about inject. So the kernel-memory thesis has
never been tested at its designed precision: 1b fired often but imprecisely; 1b-prime
fired precisely-in-intent but almost never. We cannot declare memory dead (or alive)
on a null instrument.

## Repair pre-registration (1b-prime-repair) — an instrument fix, not a re-roll

The frozen "never 1b-double-prime" clause bans iterating on a **loss**. The memory
criterion produced **no data** (2 firings), not a loss; repairing an instrument that
never engaged is not re-rolling an outcome, **provided the repair is pre-committed and
rule-derived** (Fable r10). Frozen here, before it runs:

- **Repair:** drop the mutual precision guard entirely — revert to the r9-mandated
  **distance-gate-p25-only** design (the guard was the buggy addition; the gate itself
  is sound and fires 473×). No new free parameter; no threshold chosen from a scored
  result.
- **Fresh scored seeds 25..36** — seeds 13..24 are burned (probed with provenance and
  the no-guard configuration).
- **Both branches pre-committed:** if inject now fires at measurable recall with its
  precision reported AND C still fails to beat C_reset on recurrence recovery, the
  kernel-memory thesis is dead for numerical prediction (Fable co-signs), and
  1c-or-stop follows under the 008 conditions. If C beats C_reset on recurrence
  recovery, the thesis lives.

Report inject precision and firing count every run; a null instrument is never a
verdict.

## The one line

The program has its first honest positive — a competent engine plus a detector reset
beats lookup — and, for the first time, a clean apparatus to ask whether *memory* adds
anything on top. That question is still open: the faculty has never once been tested at
the precision it was designed for. The repaired run is where it finally answers.
