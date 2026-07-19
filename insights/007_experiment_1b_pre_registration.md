# 007 — Experiment 1b: a harder world (pre-registration)

**Status:** PRE-REGISTRATION, written and committed BEFORE the world is built or
run, and going to Fable. 1a's result (006) was an honest fail: on a dense,
low-noise, linear world raw k-NN (arm E) is unbeatable ("k-NN heaven"), so the
kernel could not earn its keep. 1b is the pre-committed harder world where a model
*should* beat lookup — if it does not, that is the stronger negative result. We
freeze the spec now so a later win cannot be world-shopping.

## ELI5

The first quiz was too kind: the numbers were clean and the same rules came back
identically, so a plain notebook (look up the nearest past answer) won. The new
quiz is meaner: the numbers are noisy, the rules are **curvy** (not straight
lines), each rule visit is **short** (so the notebook has few examples), and when
a rule comes back it comes back **slightly changed** (so the notebook's old answers
are a bit wrong). Here a student who can *learn and adjust* from a few examples
should beat one who only looks up old answers. We write down exactly this quiz, and
the passing bar, before we run it once.

## Why these four changes (and only these)

Each targets a specific reason k-NN dominated in 1a, and each is a knob the pilot
already implied:

1. **Nonlinear regimes** — the rule is a curve, not a line, so the engine must
   *approximate*, not *be* the generator. This closes Fable's round-6 cheat (a
   linear engine on an AR world is the true model). The generator adds a smooth
   nonlinear term; the engine is linear over a *fixed* nonlinear feature map, so it
   can approximate the curve without being its exact form.
2. **Higher noise** — thin, noisy neighbourhoods make k-NN's averaging
   high-variance; a model that pools across a regime reduces variance.
3. **Shorter regime visits** — thin exemplar coverage per regime; k-NN starves,
   a model generalises from few samples.
4. **Perturbed recurrence** — a returning regime comes back with *jittered*
   parameters, so its windows are no longer near-identical to stored ones. k-NN can
   only regurgitate stale outcomes; the engine can *adapt* the retrieved exemplars
   to the current instance. This is the faculty under test.

## The frozen spec

**World (a `hard` config):**
- nonlinear regime map: `x_{t+1} = coef·(x_t + amp·sin(freq·x_t)) + (1-coef)·mean +
  noise·Z`, per-regime `{mean, coef, amp, freq}`.
- `noise = 0.3` (was 0.1), `seg_len = 30` (was 60), recurrence jitter `= 0.3`
  applied to a returning regime's params.
- recurrence gap still ≫ the longest context window (memory beyond the horizon).
- the four change types (recurrence, shock, drift, deceptive) as in 1a.
- deterministic in the seed; the world still owns `mu` (the true conditional mean),
  so the genie floor stays `noise·√(2/π)` regardless of nonlinearity.

**Engine (arm C):** online linear over a fixed nonlinear feature map
`φ(window) = window ++ [sin(x_last), x_last²]` — expressive enough to approximate
the curve, not the generator's exact `sin(freq·x)` form. Inject unchanged:
canonical exemplars (raw windows + outcomes), replayed through the engine's own
update on a match.

**Metrics / kill thresholds:** identical to 003 — C must beat **D** (recurrence
recovery ≥2× faster) AND **E** (recovery, regret, asymptotic median+p95), with the
match threshold tuned on separate seeds. No change to the referee.

## Hypothesis and what would falsify it

**Hypothesis:** in the hard world, E degrades faster than C (poor perturbed
matches, high-variance averaging, no extrapolation of the curve), so **C beats E**
on recovery and regret and beats D on recurrence recovery.

**Falsified if:** C fails to beat E on the primary metrics in the hard world. That
would be the stronger negative result — the kernel is dead weight even where it
should shine — and the response is *not* another world, but to question the
kernel/inject design itself.

## Open for Fable

1. Are the nonlinear generator and the fixed-feature linear engine a *fair*
   pairing, or is the feature map secretly tuned to the generator's `sin` term
   (re-introducing the model-match cheat)?
2. Is perturbed recurrence the honest lever for "engine adapts vs lookup
   regurgitates", or does the jitter just add noise that hurts both equally?
3. Is there a version of this world that makes C win *too easily* (a strawman E),
   and how would a reviewer detect that from the reported numbers?
4. The one change that, if wrong, makes a 1b "C beats E" meaningless.
