# 006 — Arm C: the kernel contestant, and what `inject` means here

**Status:** DRAFT, going to Fable for red-team (specifically the inject
mechanism). Arm C is the implementation of the 004 contract for the numerical
pilot; it is the first time the kernel is asked to earn its keep. The pilot
already set the bar (005 findings): C must beat both **D** (the detector) and **E**
(pure k-NN memory), or it is "a database with extra steps".

## ELI5

The dumb yardsticks are in: an alarm-only student (D) and a notebook-only student
(E). Now we build the real one (C): it has the **alarm** (notices a change), the
**notebook** (remembers past rules), *and* a small **learner** that actually fits
the current rule. The clever bit is how the notebook helps the learner: when the
alarm fires and the notebook recognises the situation ("this is the Tuesday rule
again"), it hands the learner the settings that worked last time, so the learner
starts warm instead of from scratch. If the situation is new, the learner starts
cold, like the alarm-only student. C should beat the alarm-only student (because it
remembers) and beat the notebook-only student (because it actually fits the rule
instead of just looking up the nearest old answer).

## The pieces (004, realised for the pilot)

- **Detector** (same as arm D): EWMA of surprise; a spike means "regime changed".
- **Canonical memory**: entries keyed in the kernel-owned canonical space. For the
  low-dim pilot the canonical key is the **raw recent window** (004 option 1;
  option 2, a learned encoder, is deferred to richer sensors). Each entry stores a
  regime **signature** (the key) and the **engine parameters** that worked in that
  regime.
- **Engine** (swappable): the pilot engine is an **online linear predictor** —
  next = w·window + b, weights updated online (recursive least squares / gradient).
  Deliberately *not* the AR conditional-mean form, so the engine does not secretly
  match the generator's model class (that would be cheating; see open question 2).
- **inject** (the crux): on a detected shift, query memory with the current
  canonical key. On a near match (a recurring regime), **warm-start the engine's
  weights from the stored parameters** for that regime. On no match (novel shock),
  **cold-reset** the engine, exactly like D.

## Why this isolates the two comparisons the pilot demands

- **C vs D** = does memory help beyond a detector? On a *recurring* regime, C
  warm-starts and recovers near-instantly; D must re-fit from scratch. If C does
  not beat D on recurrence recovery, the memory is inert.
- **C vs E** = does the engine add value over its own raw retrieval? Within a
  regime, C's fitted linear model should track the signal better than E's noisy
  nearest-neighbour lookup, so C's asymptotic error and regret beat E. **If C ≈ E,
  the engine adds nothing over the database** — the exact confound arm E exists to
  expose, now testable.

## Open for Fable (inject, specifically)

1. **Is parameter warm-start a real `inject`, or does it collapse C into "E with a
   smoother head"?** The engine's warm-start values come from memory; is C then
   just retrieval wearing a linear hat, so C-vs-E can't isolate an engine
   contribution?
2. **Engine fairness.** An online linear predictor over the window — does it still
   implicitly match the AR generator (a linear model on an AR process is nearly
   optimal), re-introducing the "generator family matches the engine" cheat? What
   engine would test "the engine adds value" without either matching the generator
   or being a strawman?
3. **Canonical key = raw window.** Fine for the pilot, or does keying memory on the
   raw window make the memory match trivially good (recurring regimes have
   near-identical windows), inflating C's recurrence advantage unfairly?
4. **What silently invalidates the C result** — the one thing that, if wrong, makes
   "C beat D and E" mean nothing?
