# 014 — Experiment M1: self-audit economics (pre-registration)

**Status:** **CLEARED by Fable (round 14), frozen, build-ready.** The draft had two
holes — a precision-only metric gameable by under-extraction (found writing the note)
and a spurious-grounding checker bias for short tokens (found on re-read, before
building — the cheapest possible time). Both are closed below within the
mechanical-no-judge premise; the checker fix turns the task into *attributed*
extraction, which is the production task of a provenance-first commons, so the repair
is also a realism upgrade. This is the first experiment on a *present-tense* faculty
(self-audit), the class 011's staleness wall cannot touch, and it builds the program's
first **cost ledger**.

## ELI5

Our minds have a "check your work" button (draft, then re-read and fix), off because
it doubles the compute and nobody measured if it helps. We ask exactly that, on a task
a dumb machine can grade: pull facts from a news item, each fact carrying the exact
sentence it came from, and check that sentence is really in the article. If checking
your work deletes more made-up facts than real ones and pays for its extra compute,
the button earns its place. If not, off was right. All rules frozen before we run —
including the sentences we'll be allowed to say either way.

## Why this faculty, why now

- **It escapes 011.** Self-audit reads the *current* input; no stored past to go stale.
- **The instrument exists.** `HECATE_MIND_MINDFULNESS` (draft+verify, ~2× calls) is
  built and *off* — disabled for throughput, never evaluated for quality.
- **It forces the ledger.** Per-call token accounting is the missing cost instrument.
- **Live only under asymmetry** (Fable r13): verification helps where *checking is
  mechanically easier than generating*. Mechanically-checkable attributed extraction is
  such a task; the smooth-AR arena is not (its residual is irreducible noise — nothing
  to catch).

## Governing principle (Fable r14)

**Free constants are tolerable on VOID conditions (they gate validity) and never on
KILL criteria (they gate verdicts).** Every tunable knob below lives on the void side;
the kill criterion is a constant-free rule.

## The frozen spec

- **Task:** attributed fact extraction from a FROZEN feed corpus — per item, extract
  {entities, dates, numbers, quoted attributions}, and **each field carries a verbatim
  evidence snippet from the source**. Frozen item set, N pre-registered, sampled before
  scoring; a disjoint calibration slice for headroom.
- **Ground truth — mechanical only, no judge, no rubric. Frozen checker rule:**
  > Every extracted field must include a verbatim evidence snippet from the source,
  > **minimum 15 characters** (quoted attributions serve as their own snippet, minimum
  > 20 characters). A field is **GROUNDED** iff (a) the snippet is a substring of the
  > source; (b) the field's surface value occurs within the snippet; (c) field-class
  > specificity holds — **dates** in the full surface form used by the source (bare
  > years insufficient), **entities** of at least 2 tokens or 6 characters, **numbers**
  > accompanied within the snippet by at least one non-numeric token. A field with a
  > missing or non-matching snippet is **UNGROUNDED**. Fields failing (c) are excluded
  > from **both** arms' counts symmetrically, with per-arm exclusion counts reported.
  > All string comparison after frozen normalization: **NFKC, casefold, whitespace
  > collapse, quote/dash unification.**

  This checks **grounding-with-attribution**, not semantic correctness or completeness.
  The snippet+specificity floor removes the short-token channel (a "3" occurs by chance
  in any article, but not inside a 15-char span the model must reproduce) *symmetrically*
  across arms, so the arm-dependent length bias cannot reach the metric. Normalization
  is part of the checker, not an implementation detail (curly quotes / NBSPs otherwise
  manufacture fake ungrounded counts). A checker bug found later is a signed amendment,
  never a silent retune.
- **Arms, paired per item:** `single_pass` vs `draft_verify` (the built, disabled
  MINDfulness path). Same model, context, items.
- **Ledger:** prompt + completion tokens and wall-clock per item, both arms, from
  provider usage. First real cost instrument; outlives the experiment.

## Kill criterion (constant-free, both legs required)

- **L1 (precision):** mean **ungrounded** fields per item falls by ≥ 50% relative,
  paired, above item-sampling noise. Counts, not rate — so shrinking the denominator
  cannot help.
- **L2 (discrimination):** the absolute paired drop in **grounded** fields per item is
  **smaller** than the absolute paired drop in **ungrounded** fields per item — *the
  audit must delete more garbage than good material.* No tunable constant.

L2 kills every gaming path: extract-nothing passes L1 but drops grounded far more than
ungrounded (fails L2); indiscriminate deletion removes fields in proportion to
prevalence (mostly grounded, fails L2); only genuine discrimination passes. Report
grounded/ungrounded yield change and extraction counts per arm always.

## Token ceiling (structurally derived, Fable r14)

Not a round number. Measure the token multiple of the `draft_verify` call graph on the
**calibration** slice (verify re-reads item + draft; structural floor ~2.1–2.4×),
**freeze ceiling = measured calibration multiple × 1.1 before the confirmatory run.**
If the confirmatory multiple exceeds the frozen ceiling → **void** (wasteful
implementation, an engineering fact), not kill. A pass requires L1 ∧ L2 ∧ tokens/item ≤
frozen ceiling.

## Void conditions (pre-declared; the e_adjudicates lesson)

Measured on the calibration slice **after the snippet checker is frozen** (the stricter
checker shifts the base rate):
- `single_pass` base **ungrounded** rate < **5%** → nothing to catch, **void not kill**
  (and its reading is decision-grade: *attribution discipline in the prompt suffices;
  the audit pass is unnecessary*).
- base ungrounded rate > **40%** → extraction task broken, **void**.
- **Model/stack version change mid-run** → void; pin model version, pin temperature
  (0 if honored), interleave arms in one run window.
- **Parse failures:** items where either arm emits unparseable JSON are excluded from
  paired scoring; parse-failure counted per arm; a differential parse-failure rate > 5
  points **blocks signing** until explained.
- **Truncation:** any output hitting the token limit is a parse-class failure (same
  handling).
- **Retries count in the ledger** — a retry loop is a cost the economics must eat.
- **Corpus hygiene frozen with the corpus** (before N is sampled): language filter,
  length ceiling vs context window, malformed-item exclusion.

## The two signed sentences, pre-written (Fable r14)

Frozen before the result exists, so the verdict can't drift:
- **On a pass:** *On mechanically-checkable attributed extraction from the frozen
  corpus, draft+verify cut ungrounded fields by ≥50% while deleting more ungrounded
  than grounded material, within the structurally-derived token ceiling — self-audit
  earns its compute on this checkable subtask. Scope: attributed extraction only; it
  does NOT generalize to free-form synthesis (symmetric, uncheckable).*
- **On a fail:** *On mechanically-checkable attributed extraction from the frozen
  corpus, draft+verify failed [L1 / L2 / the token ceiling]; the deployed minds' only
  built untested faculty does not earn its compute on its most audit-favourable
  workload, and the throughput-off decision was right.*

## Build scope

Language-stack Erlang in `hecate-spartan`, reusing `spartan_mind_llm` + the provider
carousel. Build: (1) frozen corpus snapshot + disjoint calibration slice; (2) extraction
prompt + JSON schema *with evidence snippets*, single-pass and draft+verify variants;
(3) the frozen mechanical checker (normalization, snippet match, specificity floors);
(4) token/usage capture through the client (the ledger); (5) a paired runner + referee
applying L1/L2, the token ceiling, and the void logic. Home: a self-contained,
reproducible eval mirroring the arena's world/referee/contestant discipline.

## Odds (Fable, honest)

~60% it dies at the bar; ~25% passes cleanly; ~15% voids on low base error — itself a
useful, decision-grade fact.

## Next

Build once, run once, sign whichever pre-written sentence the checker selects.
