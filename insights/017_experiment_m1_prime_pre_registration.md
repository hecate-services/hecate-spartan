# 017 — Experiment M1′: self-audit economics, re-registered (pre-registration)

**Status: DRAFT, not gated, not built.** Programme S2. Supersedes the *run* of
[014](014_experiment_m1_self_audit_economics_pre_registration.md), not its
question or its kill criteria. [016](016_experiment_m1_result_an_instrument_failure.md)
signed M1-as-run an instrument failure; this is the repaired instrument.

The question is unchanged: **does draft-then-verify earn its ~2x compute on
attributed extraction?** The kill criteria L1 and L2 are unchanged and are NOT
re-opened. Only the instrument is fixed, in the three ways 016 named, plus the one
config change 016 flagged as declarable.

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

## Fix 2 — persist per-item raw outputs (instrument hygiene)

Every call's raw response, both arms, both draft and verify passes, is written to
a per-item record alongside the ledger: item id, arm, pass, raw text, usage,
`finish_reason`, parse outcome (ok / truncated / malformed). So a future blocker is
diagnosable from retained data rather than from a summary. The run's own inability
to explain its blocker was defect 2; this closes it.

The raw-output store is committed with the feed as part of the four-artefact
record.

## Fix 3 — size the corpus for power to test L1 at its FROZEN threshold

This is where 016 was itself loose: it said n=79 was "~4x too small." That was
sizing to the wrong target.

**L1 tests a 50% relative reduction, not the observed one.** Powering to detect
the run's observed 27.8% effect would only confirm a sub-threshold effect (27.8% <
50% fails L1 on magnitude regardless of power), which is near useless. The honest
target is: n such that IF draft_verify truly cuts ungrounded fields by ≥50%, the
run can show it above sampling noise (the referee's `mean(D) > 2·SEM(D)` gate).

Sizing to the threshold effect (base ungrounded 0.228 → a 50% cut is a paired
difference of 0.114), using the run's own base rate as the pilot:

| paired-arm correlation | scored-n for the t=2 gate |
|---|---|
| 0.0 (conservative, independence) | 105 |
| 0.3 | 75 |
| 0.5 | 56 |

Base ungrounded rate held near 0.145, and ~73% of confirmatory items scored (both
arms parsed) in the run, so **scored-n ≈ 0.73 × confirmatory-N**. To clear the
conservative 105 with margin, **confirmatory-N ≥ 165**, so a corpus of **≥ 220
items** (a 25% calibration slice leaves ≥165 confirmatory). Run 1 had 108
confirmatory, so it was ~1.5× under at conservative correlation, not 4×. 016's
"4×" is corrected here.

**The number that is frozen is the corpus SIZE and the sizing rule, declared now,
before harvesting.** The effect size in the calculation is the frozen 50%
threshold, not a pilot point estimate, so this is not effect-size shopping.

## Open question for the DESIGN gate: base rate vs corpus size

The base ungrounded rate (0.145) is low, so ungrounded events are sparse and power
comes expensively per item. Two ways to buy power, and one of them may be cheating:

1. **More items at the same distribution.** Clean, expensive, ≥220 items. No bias.
2. **Enrich toward fact-dense items** (longer articles, higher base rate). Cheaper,
   but it changes the corpus distribution after seeing that the first one was
   sparse, which is a distribution chosen post-hoc. My instinct is that (2) is
   corpus shopping and (1) is the only honest option, but the gate should rule.

If the honest answer is (1) and ≥220 English items cannot be harvested cleanly from
the available EU feeds under the frozen hygiene, then M1′ is **blocked on corpus
volume**, and saying so is better than enriching to hit the number.

## What is NOT changed

- L1, L2, the void band, the token ceiling derivation, the two pre-written
  signed sentences: all frozen as in 014. Re-opening any of them on the strength
  of a run would be the drift the pre-registration exists to prevent.
- The pinned endpoint: `qwen2.5:7b-instruct-q4_K_M`, temperature 0, no rotation,
  no rate limit (kept from the M1 run, which validated it: zero retries across 143
  items).

## One config change, declared not slipped

`MAX_TOKENS` may be raised above 2000, because the cap is not a ledger cost (actual
completion tokens are, and they are ledgered) and an artificially low cap is what
made truncation bite. Raising it reduces truncation without touching what is
measured. It is a change to frozen config, so it is declared HERE, with the new
value pinned in the registration, not adjusted during a run. Candidate: 4000,
chosen from the run's observed completion-token distribution once the raw outputs
of a *calibration-only* pilot are in hand (a calibration pilot is not the scored
confirmatory slice, so it does not spend the once-only scoring).

## The signed sentences, unchanged from 014

Frozen there, repeated here so M1′ carries them:
- **Pass:** *On mechanically-checkable attributed extraction from the frozen
  corpus, draft+verify cut ungrounded fields by ≥50% while deleting more ungrounded
  than grounded material, within the structurally-derived token ceiling. Self-audit
  earns its compute on this checkable subtask. Scope: attributed extraction only.*
- **Fail:** *On the frozen corpus, draft+verify failed [L1 / L2 / the token
  ceiling]. The deployed minds' mindfulness-off default stands.*

## Odds

016's power-robust finding (draft_verify deletes grounded 8:1 over ungrounded)
already points hard at an L2 failure, and L2 needs no power at all to read as a
direction. So M1′'s most likely outcome is a **signable** FAIL on L2, which is the
verdict M1-as-run could not sign because its instrument was defective. The value of
M1′ is not a new answer; it is the RIGHT to state the answer the first run pointed
at but could not earn.

## ELI5

Last time the test broke in three ways. This registers the fixed test, in advance,
so nobody can accuse us of fiddling it after seeing results.

Fix one: teach the test to notice when the AI's answer got cut off, and count that
as its own kind of failure instead of blaming the method. Fix two: keep the AI's
actual answers this time, so if something breaks we can see why. Fix three: use
enough test items that the main measurement is trustworthy.

The interesting correction: last time I said we needed four times as many items.
Doing the arithmetic properly, we need about one and a half times as many, because
the honest question is "can the double-check cut errors in half," not "can it match
the smaller effect we happened to see." I got that wrong in the write-up of the
last run and I am fixing it here rather than quietly.

One thing we are being careful about: the easy way to get a trustworthy number
faster is to pick juicier articles. But choosing the articles after seeing that the
first batch was thin is exactly the kind of quiet cheating this whole method exists
to stop. So we either get enough plain articles honestly, or we say we couldn't.
