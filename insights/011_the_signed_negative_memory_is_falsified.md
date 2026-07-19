# 011 — The signed negative: kernel-memory/inject is falsified

**Status:** SIGNED, co-signed by Fable (round 11). The instrument repair of note 010
made the memory faculty fire (507 replays, real recall), and it added nothing over
engine+reset. The matcher-failure escape is closed at both ends by measurement: a
Bayes-optimal matcher tops out at 61.6% precision, and inject at 100% precision with
genuinely episodic retrieval is *reliably worse* than engine+reset. The kernel's core
bet — "on recognition, restore instead of restart" — loses to "always restart" even
with a perfect recognizer. That is a thesis death, not a matcher death. **STOP.**

## ELI5

We fixed the gag on the notebook and it finally spoke a lot — and it turned out the
notebook doesn't help. To be sure it wasn't just bad at *finding* the right page, we
gave a cheating student the answer key: perfect page-finding, only genuinely-old
pages. That student did *worse* than the one who just wipes the scratchpad and re-reads
today's numbers. The reason is deep and simple: the old pages are for a rule that has
since drifted a little, so replaying them drags you toward last time's answer while
the fresh data is telling you this time's. Re-learning from what's in front of you
beats remembering, whenever what returns isn't *exactly* what left. That is true in
any world where things come back changed — which is every interesting world — so we
stop here rather than shop for the one world where it wouldn't be.

## The repaired run (note 010's pre-committed instrument fix)

Dropped the buggy mutual precision guard (the units error), reverted to the
r9-mandated distance-gate-p25-only design, fresh seeds 25..36, same frozen world and
rule-derived γ=0.2513 / gate=0.3252. Inject now fires **507 times at 48.5% precision**
across all 12 seeds — real recall, precision reported.

| arm (seeds 25..36, floor 0.239) | recov τ | segReg |
|---|---|---|
| e_memory | 35.65 | 0.104 |
| f_prime (tuned engine) | 42.38 | 0.124 |
| c_reset (engine+reset, NO memory) | **28.23** | **0.089** |
| c_prime (full kernel, 507 replays @48.5%) | 29.67 | 0.089 |

`segreg_c_minus_e` = −0.015 (C beats E, reliable). `recovery_c_minus_reset` = **+1.44**
(C_prime *slower* than C_reset, within noise): memory adds nothing over engine+reset
on seg-regret and, if anything, slightly hurts recovery.

## The oracle: closing the matcher-failure escape (Fable r11)

The obvious objection — "maybe inject is fine and the *matcher* is bad (48.5% ≈ 1b's
47.5% coin-flip)" — is the mirror of note 010's instrument failure, so it had to be
measured, not argued. Two measurements close it (ported into the repo as the
`oracle` and `reset_mode` kernel diagnostics; reproduced here by hand):

- **Identifiability ceiling.** A Bayes-optimal matcher given the *true* regime
  parameters tops out at 61.6% precision on the jittered-recurrence task. The
  Euclidean matcher's 48.5% is ~79% of the information-theoretic ceiling; a better
  matcher buys at most ~13 points, forever below 62%.
- **Value at 100% precision.** The oracle arm — inject fed ground-truth regime
  identity, restricted to earlier-segment same-regime exemplars (genuinely episodic,
  *purer* than the real kernel) — fires 1091 times and is **reliably worse** than
  engine+reset:

  | arm | recov τ | segReg |
  |---|---|---|
  | c_reset | 28.23 | 0.089 |
  | c_oracle (100% precision) | 34.44 | 0.096 |

  paired `c_oracle − c_reset`: recovery **+6.2** (sd 8.1, t≈2.7), seg-regret **+0.007**
  (t≈2.7). **Dose-response:** 507 replays @48% cost +1.4 recovery; 1091 @100% cost
  +6.2 — harm is monotone in firing rate, even as precision goes to perfect.

And the last variant a defender could invoke, **reset-and-replay** (decay+reseat on
every shift, *then* replay on a match), adds nothing over pure reset (recovery +1.1,
within noise; seg-regret 0). No living memory variant remains.

## The mechanism (the actual scientific finding)

Perfect regime *identity* is not perfect exemplar *relevance*. Recurrences in this
world are jittered (mean ±0.3, coef perturbed), so even a correct-regime canonical
exemplar targets the *old* parameterization — a systematic bias comparable to the
noise floor. Replaying it displaces the reset+reseat's adaptation to live data. A
decayed engine re-learns the current regime's actual parameters from fresh
observations faster than memory can approximate them from stale ones. Restoration
loses to restart whenever what returns is not exactly what left.

## The signed sentence

> **Kernel-memory/inject thesis: FALSIFIED for numerical prediction in the
> pre-registered world class.** With a rule-calibrated engine and detector reset,
> inject at its designed operating point (507 firings, 48.5% precision, real recall)
> adds nothing over engine+reset; the identifiability ceiling for any raw-window
> matcher is 61.6% (Bayes oracle with true regime parameters, jittered recurrences);
> and inject at 100% precision with genuinely episodic retrieval is reliably worse
> than engine+reset (recovery +6.2, seg-regret +0.007, both ~2.7 sem), with harm
> monotone in firing rate. Mechanism: canonical exemplars are stale under recurrence
> jitter; restoration loses to restart even with perfect recognition. **Surviving
> positive result:** detector+reset on a competent rule-tuned engine beats k-NN over
> identical experience on segment regret — the program's only C-over-E win —
> attributable to detection and forgetting, not memory.

## Why STOP, not 1c

The oracle result predicts 1c failure: the wall is not retrieval precision and not
extrapolation, it is **exemplar staleness under parameter drift**, which any
replay-based inject inherits in any world with imperfect recurrence. A 1c designed
with *exact* recurrence to dodge staleness would be engineered-to-rescue — shopping.
If the lineage's defenders want to exhibit the surviving corner (exact recurrence +
post-shift data scarcity so severe a fast engine cannot relearn + extrapolation
demand), that is a *new* program with those scope conditions pre-declared as the
thesis's own preconditions, and the burden is theirs.

## What eleven rounds bought

The negative is earned: pre-registered before every run, red-teamed by Fable through
eleven rounds (each caught a real flaw — θ-shaped payloads, engine-matches-generator,
mesh-breaks-pairing, the arm-E confound, τ censoring, E-as-strawman, the rubber-stamp
gate, the bias re-seat, the gate circularity, the arm-F attribution, the precision-
guard units error, and finally the matcher-failure escape). The kernel was given every
chance to live. What survives is real, small, and honest: **a competent online engine
that forgets on a detected shift beats nearest-neighbour lookup over the same
experience.** Detection and forgetting earn their keep. Episodic memory replay does
not — not here, not with a perfect recognizer, not in any world where the past returns
changed.

## The one line

We set out to make the Spartan kernel produce a number that could go up. It produced
one, and the number said: forget faster, don't remember harder. That is a finding.
