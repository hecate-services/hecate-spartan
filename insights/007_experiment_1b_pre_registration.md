# 007 — Experiment 1b: a harder world (pre-registration)

**Status:** PRE-REGISTRATION, hardened after Fable's round-7 red-team, committed
BEFORE the world is built or run. 1a (006) was an honest fail: on a dense,
low-noise, linear world raw k-NN (E) is unbeatable ("k-NN heaven"). 1b is the
pre-committed harder world where a model *should* beat lookup — and if it does not,
that is the stronger negative result. Round 7 caught that the draft re-staged the
round-6 model-match cheat (a hand-picked `sin` feature), left E's freshness policy
(the real comparator) unspecified, and censored the primary metric with short
segments. All three fixed below.

## ELI5

The first quiz was too kind (clean numbers, rules returning identically), so a
plain notebook won. The new quiz is meaner: noisier numbers, **curvy** rules, and
rules that come back **slightly changed**. Here a student who can *learn and adjust*
from a few examples should beat one who only looks up old answers. Two fairness
rules we almost broke: (1) don't secretly give the learner the answer's shape (use
a *generic* set of curve-detectors, not one shaped like the rule); (2) make the
notebook student as *sharp* as possible (fast to file new pages), so beating it
means something. We freeze the whole quiz, and the passing bar, before running it.

## The frozen spec

**World (`hard` config), all knobs independent:**
- **Nonlinear, from a family.** Each regime's map is `x_{t+1} = coef·g(x_t) +
  (1-coef)·mean + noise·Z`, where `g` is drawn *per regime* from a family
  {sine, tanh, cubic, piecewise-kink} with per-regime params. No single fixed
  basis matches all regimes, so the engine must genuinely approximate.
- **Higher noise** (`0.3`), **thinner coverage** via more regimes visited less
  often (not via ultra-short segments — see the τ fix), **perturbed recurrence**
  (a returning regime's params are jittered by `0.3`, so its windows are no longer
  near-identical to stored ones).
- `seg_len ≥ 50` so `τ + H` fits inside a segment (fixes the round-7 censoring bug);
  recurrence gap still ≫ the longest context window.
- deterministic in the seed; the world still owns `mu`, so the genie floor stays
  `noise·√(2/π)`.

**Engine (arm C): random Fourier features.** `φ(window)` = random Fourier features
with frequencies drawn from a fixed, pre-registered distribution, over the whole
window (not privileging `x_last`). *Basis justification, written without reference
to the generator (the blindness test):* RFF approximate any smooth function, and
their frequencies come from a fixed distribution chosen independently of the world,
so the basis is not selected to match any particular nonlinearity. Inject
unchanged: canonical exemplars (raw windows + outcomes), replayed through the
engine's own update on a match.

**Arm E (the comparator), freshness pre-registered.** E inserts every new
`{window, outcome}` promptly (each step, bounded store, nearest-neighbour query),
so after a shift its queries match fresh exemplars within a few steps. **Equal-
effort clause:** E is given the best freshness/eviction policy we can build; a
C-win over a deliberately sluggish E is void. C-vs-E is only as strong as the
strongest E.

**Metrics / kill thresholds:** as in 003. Primary = recurrence recovery (C ≥2×
faster than D) with `seg_len ≥ 50` so τ is not censored; **co-primary = bounded
per-segment regret** (censoring-robust, so a result survives even if some τ are
undefined). C must also beat E on recovery, regret, and asymptotic median+p95.

## Confirmatory vs exploratory (round-7 discipline)

1b tests **existence** ("is there any honest world where the kernel earns its
keep"), not attribution, so a composite world is legitimate — but:
- the **composite hard world is the single primary confirmatory run**;
- a **single-lever ablation grid** (jitter-only, noise-only, nonlinearity-only,
  coverage-only) is included in this same frozen document as **labeled exploratory
  secondaries**, for attribution.
- We do NOT run escalating sequential mini-pre-registrations until C wins — that is
  world-shopping in slow motion. One frozen composite; ablations for insight.

## "Too hard" tripwires (a run is void if any trips)

- best arm's asymptotic error ≤ ~1.5× the genie floor (else nobody learned);
- all arms beat naive persistence by a stated margin;
- between-arm paired differences exceed within-arm seed noise (pilot variance is
  the estimate). "Too hard" = everyone pinned near naive with censored recoveries;
  "separating" = arms spread while the best sits near the genie floor.

## Hypothesis and falsification

**Hypothesis:** in the hard world E degrades faster than C (perturbed matches,
high-variance averaging, no extrapolation of the curve), so C beats E on the
primaries and beats D on recurrence recovery. **Falsified if** C fails to beat E:
the kernel is dead weight even where it should shine, and the response is to
question the kernel/inject design, not to soften the world.

## What round 7 changed

Replaced the hand-picked `sin` feature with **random Fourier features** + a
**generator nonlinearity family** (closes the re-staged model-match cheat);
**pre-registered E's freshness policy** + an equal-effort clause (E is the real
comparator); **`seg_len ≥ 50` + bounded-regret co-primary** (fixes τ censoring);
reframed the four levers as **one composite confirmatory + labeled ablations**; added
**"too hard" tripwires**.
