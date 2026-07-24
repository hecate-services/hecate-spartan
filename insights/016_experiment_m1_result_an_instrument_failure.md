# 016 — Experiment M1: the result is an instrument failure, not a verdict

**Status: SIGNED. Fable co-signed (CLAIM gate).** Programme S2 (self-audit
economics). Raw feed: `hecate-spartan-programmes/corpora/m1/raw-feed-20260724T161023Z.txt`,
committed marked NOT SIGNABLE. Engine pin: `qwen2.5:7b-instruct-q4_K_M`, ollama,
temperature 0.

M1 (pre-registered in [014](014_experiment_m1_self_audit_economics_pre_registration.md))
asked whether draft-then-verify earns its ~2x compute on attributed extraction.
It ran to completion on the frozen 143-item corpus. **No verdict on draft_verify
is signable from this run**, and the reason is the instrument, not the method.

## What blocked the signature

014 blocks signing on a differential parse-failure rate above 5 points. Observed
**15.7**: single_pass 7/108 (6.5%), draft_verify 24/108 (22.2%). The pre-written
FAIL sentence exists precisely so a blocked run cannot be reported as a verdict, so
it is not reported as one.

## Three defects in the instrument, two of them found only at the CLAIM gate

**1. The truncation clause was never built.** 014's void section, verbatim:
*"Truncation: any output hitting the token limit is a parse-class failure (same
handling)."* `self_audit_extract:parse_response/2` reads `message.content` and
never inspects `finish_reason`, and `parse_fields/1` returns a bare
`{error, unparseable}` with no truncation branch. So a truncated output and a
malformed-but-complete output are the same event to the referee. This is not a
subtle omission: it is a frozen requirement that was not implemented, and I missed
it because I read the code for what it did rather than against what 014 demanded.

It matters because the two draft_verify calls are asymmetric in output length: the
verify pass must reproduce a full corrected JSON, strictly longer than a single
draft, so at a fixed 2000-token cap truncation is **concentrated in draft_verify**.
The "rolls twice" null predicts `1 − (1 − 0.065)² = 12.5%`; observed 22.2% leaves a
**9.7-point residual**, and asymmetric truncation is its prime suspect.

**2. Raw per-item outputs were not persisted.** The run kept the corpus, the code,
and the summary, but not the model's per-item output. So the 24 draft_verify
failures **cannot be classified** into truncation versus malformed-format after the
fact. The data needed to explain the blocker was discarded by the run that produced
it.

**3. The confirmatory slice was underpowered to evaluate L1 at all.** This is
independent of parsing. Base ungrounded rate 0.145 over 79 scored items is ~18
ungrounded events total; a paired 50% reduction against that cannot be
distinguished from sampling noise (`above_noise=false`). L1 was never *evaluable*.
Re-running the same corpus size at the same base rate would return
`above_noise=false` again, so a re-run of this design is not the shopping pattern,
it is simply futile.

## The one thing this run did measure

Power-robust, direction-stable under both the parse gap and the power problem:
**draft_verify deleted grounded material 8:1 over ungrounded** (0.532 grounded per
item removed against 0.063 ungrounded, an 8.4:1 ratio). For selection bias to be
masking a true L2 pass, the ~17 excluded draft_verify items would have to reverse
an 8:1 ratio measured on 79. Not plausible. On this workload, the audit is not
auditing, it is destroying grounded material, and that finding survives everything
else being unsignable.

Note the framing correction Fable forced: L1 must be reported as *"not evaluable at
n=79, base rate 0.145"*, not as *"draft_verify failed to reach 50%."* Reporting a
failed threshold implies the threshold was tested; it was not.

## What is signed

M1-as-run is an **instrument failure**: the confirmatory slice was underpowered to
evaluate L1; the pre-registered truncation-as-parse-failure clause was not
implemented, so the 15.7-point differential parse gap cannot be attributed; and raw
outputs were not retained, so it cannot be attributed retrospectively. The single
power-robust observation is that draft_verify deleted grounded material 8:1 over
ungrounded (L2 direction unambiguous). This is not a verdict on whether self-audit
earns its compute; that question is unanswered.

## Why this is a re-registration, not a re-run

014 scores the confirmatory slice once, and the 143-item corpus is exhausted (35
calibration + 108 confirmatory, no fresh slice). Diagnosing defect 1 needs the raw
outputs that defect 2 discarded, so the first redo would be **diagnostic, not
confirmatory**, and re-scoring the same 108 after seeing the feed is the shopping
pattern. None of 014's candidate quick fixes is permissible: a symmetric transport
retry changes the ledger 014 froze (and a retry at the same cap truncates again);
JSON mode and a stricter instruction both edit a frozen prompt, and the verify
pass's format difficulty may be part of draft_verify's real cost, so masking it
erases signal.

**M1′ (to be pre-registered), fixing only what is a 014 clause or an honest
declaration:**
- implement the omitted truncation detection (`finish_reason == length` or
  `completion_tokens == cap`, classified parse-class per 014);
- persist per-item raw outputs, so a future blocker is diagnosable;
- size the corpus for power at base rate ~0.145 (n=79 was ~4x too small);
- `MAX_TOKENS` raised is defensible (the cap is not a ledger cost; actual
  completion tokens are) but is a frozen-config change, so it is declared in the
  new pre-registration, not slipped into a redo.

## Standing consequence

The deployed minds' `HECATE_MIND_MINDFULNESS=off` default was the throughput
decision M1 was meant to test. It **stays off**, and now on evidence rather than
convenience: the only power-robust finding is that draft_verify destroys grounded
material 8:1 on this workload. That does not need the unsignable parts.

## Method note

Two of the three instrument defects were invisible from the code and the summary,
and surfaced only when the adversary read the frozen pre-registration against the
run. The rule earns another entry: a green run against a mechanical checker is not
a clean run. The checker not implementing a frozen clause is exactly the confound
that no analysis of the summary alone can find, which is faber insight 002 and 047
recurring one level up.

## ELI5

We wanted to know if making the AI double-check its own work is worth the extra
cost. We built the test, froze the rules, ran it for three hours, and got a number
that said "not worth it."

Then we refused to believe the number, on purpose, and the adversary found three
holes in our own test. One: the rules said "if the AI's answer gets cut off
mid-sentence, count that as a formatting failure," and we forgot to build that
part. The double-check step writes longer answers, so it gets cut off more, so our
test blamed the method for something the test itself broke. Two: we threw away the
AI's actual answers, keeping only the totals, so we can't even go back and check
which failures were cut-offs. Three: the test wasn't big enough to detect the main
effect either way, so the headline number was never trustworthy.

So the honest result is not "double-checking doesn't work." It is "our test was
broken in three ways, here they are, and here is the fixed test we'll run instead."
The one thing we can still say for sure: on this task the double-check deleted eight
times more good facts than bad ones, so leaving it switched off is the right call
for now.

The uncomfortable part worth keeping: the test passed all its own unit tests and
ran green. Green is not clean. A checker that skips a rule looks exactly like a
checker that has nothing to catch.
