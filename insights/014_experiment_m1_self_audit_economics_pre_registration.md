# 014 — Experiment M1: self-audit economics (pre-registration)

**Status:** DRAFT pre-registration, designed with Fable (round 13), **pending a Fable
clearance pass before building** — because I found a hole in the design (a
precision-only metric is gameable by under-extraction) that must be closed first.
This is the first experiment on a *present-tense* faculty (self-audit), the one class
011's staleness wall cannot touch, and it doubles as the build of the **cost ledger**
the strategy debate kept demanding.

## ELI5

Our minds have a "check your work" button (draft an answer, then re-read and fix it).
It costs about twice the compute, so the team switched it off to go faster — but
nobody ever measured whether it made the answers *better*. So we don't actually know
if it's worth it. This experiment asks exactly that, on a task where "right" and
"wrong" can be decided by a dumb machine (not another AI's opinion): pull facts out of
a news item, then check whether each pulled fact literally appears in the article. If
checking-your-work cuts made-up facts enough to justify the extra compute, the button
earns its place. If not, switching it off was right. We freeze the rules before we
run.

## Why this faculty, why now

- **It escapes 011.** Self-audit reads the *current* input; there is no stored past to
  go stale. The mechanism that killed memory-inject does not apply.
- **The instrument already exists.** `HECATE_MIND_MINDFULNESS` (draft+verify, ~2×
  calls/turn) is built and currently *off* — disabled for throughput, never evaluated
  for quality. The question is unrun, not settled.
- **It forces the ledger.** Running it requires per-call token accounting — the
  missing cost instrument. One experiment, two debts.
- **But it is live only under asymmetry** (Fable r13): verification helps where
  *checking is mechanically easier than generating* (a claim vs its source document).
  Where a model just re-reads its own free-form reasoning, self-correction is
  weak-to-negative — it shares its own blind spots. So the task MUST be built in the
  asymmetric regime, or it nulls for the wrong reason. Mechanically-checkable
  extraction is such a task; the smooth-AR arena is not (its residual is irreducible
  noise — nothing for an audit to catch).

## The frozen spec

- **Task:** structured fact extraction from the live feed corpus — per item, extract
  {entities, dates, numbers, quoted attributions (speaker + quote)} as JSON. A
  **frozen** item set, N pre-registered, sampled before any scoring.
- **Ground truth — mechanical only, no judge model, no rubric.** A deterministic
  checker validates each extracted field against the source text: a date parses AND
  its surface form occurs in source; a number occurs in source; an entity name occurs
  in source; a quote is a substring of source. The source document owns the truth the
  way the arena world owned `mu`. Checker frozen before the run; a checker bug found
  later is a **signed amendment**, never a silent retune.
  - What this checks is **grounding** (is the field present in the source, i.e. NOT
    hallucinated) — the exact failure mode verification should reduce. It does not
    check semantic correctness or completeness; see the hole below.
- **Arms, paired per item:** `single_pass` (current throughput config) vs
  `draft_verify` (the built, disabled path). Same model, same context, same items.
- **Ledger:** measured prompt + completion tokens and wall-clock per item, both arms,
  from the provider usage fields. This is the program's first real cost instrument and
  outlives the experiment.

## The hole I found in the design (must close before building)

Fable's primary metric — "mechanically-detected field error rate" (fraction of
extracted fields not grounded) — is **gameable by under-extraction**: a mind that
extracts *nothing* has a zero error rate. If `draft_verify` "improves" mainly by
being more *conservative* (dropping uncertain fields), it wins the metric without
being better. Precision-only is not enough.

**Proposed fix (for Fable clearance):** a two-part kill criterion that both legs must
satisfy —
1. **Hallucination rate** (ungrounded / extracted) must fall by ≥ 50% relative; AND
2. **Grounded-field yield** (count of source-verified fields per item) must NOT drop
   by more than a pre-registered ε (e.g. 10%).
So a pass means *fewer hallucinations without extracting meaningfully less true
signal.* Report both numbers plus the extraction count per arm, always.

## Kill threshold and void conditions

- **Kill threshold:** `draft_verify` passes only if hallucination rate falls ≥ 50%
  relative AND grounded-field yield holds (within ε) AND tokens/item ≤ 2.2×, each
  paired difference exceeding item-sampling noise. Fail any leg → self-audit is dead
  *as an economic proposition for this workload*, and the throughput-off decision was
  right.
- **Void (pre-declared, the e_adjudicates lesson):** measured on a disjoint
  calibration slice before the confirmatory run — if `single_pass` base hallucination
  rate < 5%, the world cannot adjudicate (nothing to catch), void not kill; if > 40%,
  the extraction task itself is broken, void. A void that reads "base error already
  <5%" is itself a useful fact (the pipeline is accurate; throughput-off was free).
- **Scope caveat (pre-declared):** extraction is a *checkable proxy slice*, not the
  minds' generative output (discussion/synthesis is symmetric — no cheap check). A
  pass generalizes to checkable subtasks, NOT to free-form reasoning; do not over-read
  it into "mindfulness helps the society."

## Build scope

Language-stack, Erlang, reusing what exists in `hecate-spartan`:

- **Reuse:** the LLM client (`spartan_mind_llm`) and provider carousel (colibri/
  ollama Mistral + free tiers) — already there.
- **Build:**
  1. **Frozen corpus snapshot** — capture N feed items (source text + id) to a file
     before scoring; a disjoint calibration slice for the void/headroom check.
  2. **Extraction prompt + JSON schema** — single-pass and draft+verify variants (the
     verify pass re-reads the draft against the source and revises).
  3. **Mechanical checker** — date parse+occurrence, number occurrence, name
     occurrence, quote substring; pure, deterministic, frozen.
  4. **Token accounting** — surface `usage` (prompt/completion tokens) from the
     provider responses through the client (this is the ledger; verify each provider
     returns it, else measure via a tokenizer).
  5. **Paired runner + referee** — per item, both arms, compute hallucination rate,
     grounded yield, tokens; aggregate paired; apply void + kill logic.
- **Home:** a self-contained eval (mirrors the arena's world/referee/contestant
  discipline) so it is reproducible and the checker is auditable.

## Odds (Fable r13, honest)

~60% it dies at the bar (the 2.2× token ceiling is the harder leg than the quality
leg; same-model verification is only rescued here by mechanical checkability moving
the task into the asymmetry regime). ~25% it passes both legs cleanly. ~15% it voids
on headroom (base error already low) — itself a useful, publishable fact.

## Next

Fable clearance on the frozen spec (especially the under-extraction fix) → build →
one confirmatory run → sign whichever sentence the checker writes. Same discipline
that produced every honest result so far.
