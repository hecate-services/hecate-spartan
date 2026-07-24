# 017 — Experiment M1′: self-audit economics, re-registered (pre-registration)

**Status: SUPERSEDED by [018](018_self_audit_fails_l2_a_bound_beats_a_rerun.md) —
run-plan NOT built.** The DESIGN gate on this repaired instrument concluded that a
re-run was unnecessary: the L2-fail *direction* is signable from the 016 run under a
defect-robust worst-case bound (018), so no fresh corpus was harvested. This note is
retained as the record of the design that a bound made moot, and its fix 1 / fix 2
stay on the shelf for any future experiment that needs a *measured* L2 rather than a
bounded direction.

**Status when live: DRAFT 2, DESIGN-gated (Fable REJECTED draft 1), not built.** Programme S2.
Supersedes the *run* of
[014](014_experiment_m1_self_audit_economics_pre_registration.md), not its
question or its kill criteria. [016](016_experiment_m1_result_an_instrument_failure.md)
signed M1-as-run an instrument failure; this is the repaired instrument.

The question is unchanged: **does draft-then-verify earn its ~2x compute on
attributed extraction?** The kill criteria L1 and L2 are unchanged and are NOT
re-opened.

**What M1′ actually delivers, corrected at the gate.** Draft 1 framed this as an
L1-power run and sized a 220-item corpus to earn an L1 verdict. That framing was
wrong twice: the sizing was at 50% power (a coin flip, Finding A below), and L1 is
**un-makeable-fair at its own threshold for any n** (Finding B below). The gate's
reframe, adopted: **M1′ is an L2-VALIDITY run.** 016's power-robust finding
(draft_verify deletes grounded 8:1 over ungrounded) was computed on the 79
*non-truncated* items, and the direction of that truncation-selection bias is
**unknowable from retained data** because the outputs were discarded (defect 2).
Fix 1 and fix 2 convert that unknowable bias into a known, bounded, reported one.
**That** is what M1′ buys: the right to sign the L2 direction under a clean
instrument. L1 is a secondary readout carrying its boundary limitation, not the
deliverable.

## Why a re-registration and not a re-run

014 scores the confirmatory slice once, the 143-item corpus is exhausted, and
diagnosing the truncation defect needs the per-item outputs the run discarded. So
a redo on the same slice is diagnostic, not confirmatory, and re-scoring after
seeing the feed is the shopping pattern. M1′ is a fresh registration with a fresh
corpus.

## Fix 1 — implement the truncation-as-parse-failure clause (a frozen 014 clause)

014 already requires it, verbatim: *"Truncation: any output hitting the token
limit is a parse-class failure (same handling)."* The run did not implement it, so
`self_audit_extract:parse_response/2` will inspect the completion and classify an
output as **truncated** when `finish_reason == length` (OpenAI shape) OR
`completion_tokens == max_tokens` (the cap actually sent). A truncated output is a
parse-class failure, counted and reported **separately** from a malformed-format
failure, so the two are never again the same event.

This is not a new rule. It is building a rule 014 froze and the run skipped.

## Fix 2 — persist per-item outputs AND per-item paired counts (instrument hygiene)

Every call's raw response, both arms, both draft and verify passes, is written to
a per-item record alongside the ledger: item id, arm, pass, raw text, usage,
`finish_reason`, parse outcome (ok / truncated / malformed). So a future blocker is
diagnosable from retained data rather than from a summary. The run's own inability
to explain its blocker was defect 2; this closes it.

**Also persisted: the per-item paired counts** (grounded and ungrounded per arm,
per item), not only the raw text and the aggregates. Draft 1 listed the raw text
but not these, and the gate caught it: the *reason* fix 3 below has to reconstruct
the variance from a Poisson proxy is precisely that the M1 run persisted aggregates
only, so the empirical `Var(D)` the referee actually saw could not be recovered.
With per-item paired counts retained, no future sizing ever needs the proxy again.

The raw-output store is committed with the feed as part of the four-artefact
record.

## Finding B — L1 cannot be made a fair test at its own threshold, for any n

Stated in the registration because the gate required it: sizing must not imply a
fairness the rule does not have.

L1 is a conjunction on a **point estimate**: observed relative reduction >= 50% AND
`t > 2`. At a true effect of exactly 50%, the point estimate is symmetric about
50%, so the magnitude leg passes ~50% of the time **for any n** -- tightening the
confidence interval does not move a symmetric estimate off its own mean. The
magnitude bar sits at 50% while the noise bar sits at zero; they test different
nulls. So a genuinely-50% faculty is failed by L1 a large fraction of the time no
matter how large the corpus.

L1 is frozen and not re-opened. The consequence for M1': **L1 is only decisively
resolvable when the truth is far from 50%.** Near threshold it is a coin flip by
construction, and no corpus size fixes that. M1' reports L1 as a secondary readout
with this boundary stated, and does not claim to have given L1 a fair test.

## Fix 3 -- size for L2 validity, not L1 power

Draft 1 sized a 220-item corpus to earn an L1 verdict. The gate rejected it on two
counts, both checkable arithmetic.

**Finding A -- the table was 50% power.** The referee gate is `mean(D) > 2*SEM(D)`.
Sizing so `E[t] = 2` makes `P(t > 2) ~ 50%`: the run clears the bar half the time.
For 80% power the target is `E[t] ~ 2 + z_0.80 = 2.84`, scaling n by
`(2.84/2)^2 ~ 2.0`. So the honest L1 numbers are double the draft's:

| paired-arm correlation | scored-n, 50% power (draft) | scored-n, 80% power |
|---|---|---|
| 0.0 (conservative) | 105 | **212** |
| 0.3 | 75 | 152 |
| 0.5 | 56 | 112 |

At 80% power and the conservative correlation, confirmatory-N ~ 290 and the corpus
~ 390. **Draft 1's "1.5x under" was half a correction:** the effect-size target was
fixed, the power level was not. The Poisson `var ~ mean` proxy under-sizes further,
because ungrounded errors clump on hard items (over-dispersion, `Var > mean`),
pushing the same way. A real L1-power run is ~3-4x the original, not 1.5x.

**M1' does not pay that, because L1 is not its deliverable.** Given Finding B (L1 a
coin flip near threshold) and 016 (the faculty is heading for an L2 fail, which the
8:1 ratio already shows without power), sizing 390 items to decide L1 is the tail
wagging the dog.

**M1' is sized for L2 validity instead.** L2 is a direction, not a point estimate
against a threshold, so it needs a clean instrument far more than a large n. A
corpus **near the original 108 confirmatory** re-establishes the 8:1 direction under
fix 1 (no truncation confound) and fix 2 (the selection bias now measurable), which
is the thing M1-as-run could not sign. If the direction survives a clean instrument,
it signs; L1 rides along as a stated-boundary secondary.

Sizing off the **upper** bound of the variance estimate, not its point value, since
the 0.145 base rate is itself noisy at n=79.

## Corpus honesty and temporal drift

Enriching toward fact-dense items to buy a higher base rate is corpus shopping and
is out. Re-harvesting the **same feeds under the same frozen hygiene through the
same automated pipeline** is a clean fresh sample: the base rate learned from run 1
informed *sizing* (legitimate), never *selection* (which an automated harvest makes
impossible anyway).

The risk the gate named that draft 1 missed is **temporal, not selective.** "More
recent items" from RSS means a later date window, and news fact-density drifts with
the calendar. That is not shopping, but it can move the base rate out of the void
band and silently mis-power the run. Closed two ways, declared now:

- **Frozen harvest-window rule:** the corpus is the items under frozen hygiene from
  the pipeline run on a single declared date, not accumulated across days.
- **Base rate re-measured on the calibration slice before confirmatory scoring**,
  with an out-of-band calibration base rate (outside 5-40%) declared a **void** in
  advance. A drifted corpus then voids honestly instead of quietly mis-powering.


## What is NOT changed

- L1, L2, the void band, the token ceiling derivation, the two pre-written
  signed sentences: all frozen as in 014. Re-opening any of them on the strength
  of a run would be the drift the pre-registration exists to prevent.
- The pinned endpoint: `qwen2.5:7b-instruct-q4_K_M`, temperature 0, no rotation,
  no rate limit (kept from the M1 run, which validated it: zero retries across 143
  items).

## One config change, declared not slipped

`MAX_TOKENS` may be raised above 2000, because the cap is not a ledger cost (actual
completion tokens are, and they are ledgered). The gate confirmed this is clean, and
why it is clean is fix 1: with truncation detected and counted as its own parse
class, a mis-set cap costs only scored-n (power), never correctness. It cannot bias
L1 or L2, because it never changes which fields draft_verify keeps, only whether the
output is observed complete.

**The frozen quantity is the sizing RULE, not the number.** Set the cap with
headroom above the calibration maximum: `ceil(max_observed_completion_tokens × 1.5)`
rounded up to a round number, measured on a **calibration-only** pilot (which is not
the once-only confirmatory slice, so it spends nothing). 4000 is a plausible
landing point, not a pre-committed value; the rule is what is pinned.

## The signed sentences, unchanged from 014

Frozen there, repeated here so M1′ carries them:
- **Pass:** *On mechanically-checkable attributed extraction from the frozen
  corpus, draft+verify cut ungrounded fields by ≥50% while deleting more ungrounded
  than grounded material, within the structurally-derived token ceiling. Self-audit
  earns its compute on this checkable subtask. Scope: attributed extraction only.*
- **Fail:** *On the frozen corpus, draft+verify failed [L1 / L2 / the token
  ceiling]. The deployed minds' mindfulness-off default stands.*

## Why run it at all, given the answer looks decided

The honest tension the gate surfaced: 016's 8:1 already reads as an L2 fail, and L2
needs no power, so why run 108 more items? Because the 8:1 was measured on the *79
non-truncated* items, and the direction of the truncation-selection bias is
**unknowable from the data the run kept** — the excluded items' outputs were
discarded (defect 2). The bias could flatter draft_verify (its truncated outputs
were its worst audits, excluded) or malign it, and nothing retained can tell which.
Signing L2 from the existing feed now would repeat 016's own error: quoting a
verdict from a voided instrument.

Fix 1 (truncation caught, not silently scored) and fix 2 (per-item outputs and
paired counts retained) convert that unknowable bias into a **known, bounded,
reported** one. That, not an L1 number, is what M1′ buys: the right to sign the L2
direction under an instrument whose selection effect is measured rather than
guessed. If the direction does not survive a clean instrument, that too is a real
result and 016's standing consequence would need revisiting.

## ELI5

Last time the test broke in three ways. This registers the fixed test, in advance,
so nobody can accuse us of fiddling it after seeing results.

Fix one: teach the test to notice when the AI's answer got cut off, and count that
as its own kind of failure instead of blaming the method. Fix two: keep the AI's
actual answers this time, so if something breaks we can see why. Fix three turned
out to be a trap I nearly walked into twice.

The trap: I first said we needed four times as many articles, then corrected that to
one and a half. The adversary showed BOTH were wrong. My "one and a half" was still
sized so the test passes by luck half the time, and worse, the pass/fail line I was
sizing for is fundamentally a coin flip when the true answer sits right on it, no
matter how many articles we use. Chasing a bigger pile of articles to settle that
question is the tail wagging the dog.

The real point of re-running is smaller and more honest: last time the AI's cut-off
answers were quietly thrown out, and we can no longer tell whether that made the
double-check look better or worse than it is. The fixed test keeps those answers, so
this time we can measure it instead of guessing. That is the thing worth 108
articles. The headline "is it worth the cost" verdict was already pointing one way,
and this earns the right to say so cleanly.

One thing we are being careful about: the easy way to get a trustworthy number
faster is to pick juicier articles. But choosing the articles after seeing that the
first batch was thin is exactly the kind of quiet cheating this whole method exists
to stop. So we either get enough plain articles honestly, or we say we couldn't.
