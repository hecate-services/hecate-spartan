# 018 — Self-audit fails L2: a defect-robust bound, and no re-run

**Status: SIGNED. Fable co-signed (DESIGN gate on M1′ concluded "build nothing").**
Programme S2. Supersedes the *run-plan* of
[017](017_experiment_m1_prime_pre_registration.md): M1′ is not built.
Result of the question in [014](014_experiment_m1_self_audit_economics_pre_registration.md),
recovered from the [016](016_experiment_m1_result_an_instrument_failure.md) run
without a second run.

## The claim

**On mechanically-checkable attributed extraction, draft-then-verify fails L2: it
deletes more grounded material than ungrounded, and that direction is robust to
every instrument defect 016 declared.** L1 is unresolved (boundary-limited, see
016 and 017). Self-audit does not earn its compute on this workload.

## Why no re-run was needed

016 signed M1-as-run an instrument failure and could not sign L2, because the 8.4:1
grounded-to-ungrounded deletion ratio was measured on the 79 non-truncated items,
and the direction of the truncation-selection bias on the 29 unscored items was
unknowable from discarded outputs. 017 proposed a clean 108-item re-run to measure
it.

The re-run is unnecessary. A bound built to **maximally favour the conclusion we do
not want** (an L2 pass) cannot reach it.

- On the 79 cleanly-scored items, draft_verify deleted grounded over ungrounded by
  a net `(0.532 − 0.063) × 79 = 37.05` deletions. For the full 108 to flip to an L2
  pass, the 29 unscored items must contribute ≥ 37.05 net **ungrounded-over-grounded**
  deletions.
- Assign them the maximally flip-favourable counterfactual: zero grounded
  collateral, and every ungrounded field deleted. Then each unscored item needs
  `u > 37.05 / 29 = 1.28` ungrounded deletions.
- The corpus ungrounded density is 0.228 per item (single_pass arm). So `u > 1.28`
  requires the unscored items to be **5.6× ungrounded-denser than average**, while
  also deleting perfectly and with zero grounded loss. At a generous 5× density the
  contribution is 33.1, still short of 37.05. It does not flip until 5.6×.
- **The truncation physics run the other way.** draft_verify truncates on *long*
  outputs, which are outputs that *kept* many fields, i.e. deleted little — the
  L2-*unfavourable* items. The flip counterfactual (dense items, heavy correct
  deletion, hence short output) is the set *least* likely to have truncated. The
  real selection pressure on the unscored set pushes L2 worse, not better.

A flip would require the unscored items to be simultaneously 5.6× denser, perfectly
discriminating, zero-collateral, and truncated for a reason opposite to the
deletion physics. That is not a plausible selection bias; it is a contrived
adversarial one.

**The bound is defect-robust by construction:** it uses only the cleanly-parsed 79
(untouched by truncation) plus a content ceiling on the unscored 29. It therefore
survives exactly the defects 016 declared, which is what licenses signing a
direction from a run that was itself signed an instrument failure. The argument was
built not to depend on the broken parts.

## What is signed, and the two honesty constraints

- **The direction** `drop_grounded > drop_ungrounded`, robustly. **Not the 8.4:1
  magnitude** — that ratio is subset-conditional (the 79 clean items), and there is
  no full-set claim to it.
- **L1 unresolved**, not failed: boundary-limited (a point estimate at a 50%
  threshold is a coin flip near truth, 017 Finding B) and underpowered (016). The
  014 fail sentence is filled in with **L2 only**, scoped to "direction robust under
  a documented worst-case bound on the unscored items."

The 014 signed FAIL sentence, instantiated:

> On the frozen corpus, draft+verify failed L2 (it deleted more grounded than
> ungrounded material, direction robust under a documented worst-case bound on the
> unscored items). L1 is unresolved. The deployed minds' mindfulness-off default
> stands.

## Standing consequence

`HECATE_MIND_MINDFULNESS=off` was a throughput decision made on convenience. It now
stands on **evidence**: on this workload the audit destroys grounded material rather
than removing garbage. Nothing operational changes — the default was already off —
but its justification is upgraded from "we could not afford it" to "it makes the
output worse, measured." No mind should turn it on for attributed extraction.

The scope is exactly attributed extraction, the mechanically-checkable subtask.
This says nothing about self-audit on free-form synthesis, which is uncheckable and
was never in M1's scope.

## The meta-result: a bound can beat a re-run

Running 108 fresh items to confirm a direction that a conservative bound already
forces is ritual, not rigour — the same over-spend as draft 1's 390-item L1 plan,
just pointed at a conclusion instead of away from one. The discipline that closed
this cheaply: after the CLAIM gate declared the instrument broken, the DESIGN gate
on the *repair* asked not "how big a clean run" but "is a clean run necessary at
all," and the answer was a fifteen-line arithmetic bound.

The instrument defects were still worth fixing for the *next* experiment (017's fix
1 and fix 2 stay on the M1′ shelf if a future question needs a measured L2 rather
than a bounded direction). But this question did not need them.

## Programme S2 status

**CLOSED on L2, OPEN on L1.** Self-audit's cost is not justified for attributed
extraction (L2, signed). Whether it would pass L1 at a true effect far from the 50%
threshold is unresolved and, per 017 Finding B, unresolvable at threshold by the
frozen rule. Reopening L1 would need a different decision rule, which is a different
pre-registration, and there is no live reason to write it: the L2 result already
answers the deployment question.

## ELI5

Last time we ran a three-hour test and the test itself turned out to be broken, so
we could not trust the headline number. We were about to run a fixed version of the
test on fresh articles.

Then we did the arithmetic and realised we did not have to. On the articles the
broken test *did* handle cleanly, the AI's double-check deleted good facts far more
than bad ones — badly enough that even if every article the test dropped had gone
the perfect opposite way, it could not change the overall answer. And the reason
articles got dropped actually pushes the answer the same direction, not against it.

So the double-check makes the extraction worse, and we can say that from data we
already have, without spending another three hours. The AI's self-check stays
switched off for this kind of task, now because we measured that it hurts, not just
because it was expensive.

The lesson worth keeping: the honest move was not "run a bigger test." It was to ask
whether the test was needed at all, and the answer was a page of arithmetic instead
of three hours of compute. A good bound can be worth more than a good run.
