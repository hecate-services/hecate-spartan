# 005 — The experiment as three mesh services

**Status:** red-teamed (round 5). Verdict: the right *deployment* story for the
league/federation phase, but the **pilot runs local-first** — running it over the
mesh would break 003's paired statistics. See the Decision at the end. Origin: the
operator's proposal to translate the program (003 metric, 004 contract) into
hecate-om services — **hecate-world / hecate-referee / hecate-contestant**,
the contestant being a Spartan.

## ELI5

Split the experiment into three players so nobody can cheat:
- a **world** that sets the puzzles,
- a **referee** that keeps the scorecard and the sealed answer key,
- the **contestant** being tested (a Spartan).

They talk over the mesh. The contestant only ever guesses the *next* step before it
happens, and the referee holds the answers, so the contestant literally cannot
peek. And because many contestants can face the same world and referee, you get a
**league table** — which is how you get real selection (the good rise) and a
public, tamper-proof record of who actually predicted well.

## Why this is the right shape

The single hardest requirement in 003 was **no scorer leak / no peeking**, enforced
by discipline ("don't look at the answers"). Splitting into three services turns
that discipline into **architecture**: the thing that could cheat cannot reach the
answers, because the answers live in a different service it has no read path to.
That is a real upgrade, not just tidiness.

The three roles map cleanly onto the experiment:

| Service | Owns | Is |
|---|---|---|
| **hecate-world** | the sensor stream + the hidden regime schedule | the world |
| **hecate-referee** | the frozen pre-registration, the answer key, `e*_r`, the arms, the metrics, the kill thresholds | the neutral referee + registrar |
| **hecate-contestant** | a kernel + engine (the 004 contract) | the Spartan under test |

The arms of 003 (A/B/D/E and C) are simply **different contestant configurations**
facing the same world, scored by the same referee. Swapping the engine
(LLM vs net) is swapping a contestant. Nothing else moves.

## Three refinements

**1. The referee publishes a signed, tamper-evident pre-registration.** It holds
the frozen metric, `e*_r` (from separate genie rollouts), the arm definitions, the
kill thresholds, the changepoint labels, and the ground-truth outcomes — none of
which the contestant can read. Before a run it publishes the pre-registration as a
signed mesh fact (content-addressed, so it cannot be edited after the fact); after
the run it publishes the result against that same hash. This is how "frozen before
the run, no peeking" becomes *auditable* in a sovereign way, and it is the public,
compounding track record 001 said the society lacked — now a real artifact.

**2. The world has two modes, never mixed.**
- **Frozen** (seeded, pre-registered) for the falsification experiments (001-004).
  Determinism is the point; the generator family is frozen before the retrieval key.
- **Adaptive / co-evolving** for the open-endedness phase later (a POET-style world
  that probes the contestant's weaknesses, generates deceptive regimes, escalates).
  This is where open-endedness actually lives — but it *breaks* pre-registration, so
  it is a different mode for a different question. Same service, a mode flag, never
  both in one experiment.

**3. The mesh is the OUTER loop only.** Predict-*ahead* per step over the mesh is
fine for a falsification run (thousands of steps): the contestant commits its
prediction for `t+1` at time `t`, the referee scores it when `t+1` arrives — no
barrier, no way to peek. **But neuroevolution needs millions of cheap rollouts, and
those cannot go over the mesh** (latency would make it geologic). So the evolution
*inner loop* stays **in-process inside the contestant**; the mesh harness only
challenges, scores, and ranks *finished* contestants. Mesh = tournament substrate;
in-process = training. Conflating them would be a fatal performance mistake.

## What it unlocks (the part that is better than expected)

Once arms are contestants and the referee ranks them, you have a **league**: many
contestants (different arms, engines, kernels, and eventually different people's
Spartans on their own nodes) all facing one world, ranked by one neutral
referee, with a signed public record. That gives, honestly:
- **selection** — the good rise, the bad are culled (001's missing pressure),
- **accumulation** — the signed track record is the compounding artifact 001 lacked,
- **federation** — sovereign, mesh-native, anyone can enter a contestant.

**Not** division of labour, and this is Fable's correction to an oversell: ranked
rival predictors are still N interchangeable opinion-generators, now with scores.
Competition is not super-additivity. (The three *roles* — world/referee/contestant
— are a real division of labour at the harness level; the *contestants* are not.)
So the league is the "society with **stakes**" 001 wanted, but it is not yet a
society of minds that compose. Don't conflate the two.

## It also resolves the language question toward BEAM

003 left open a Python-vs-BEAM tension. hecate-om pushes the answer to BEAM, and
that is now viable rather than dogmatic: Gene Sher's neuroevolution lineage (DXNN)
*is* Erlang, and faber-tweann is the natural net-engine contestant. The world
(a seeded generator) and referee (scoring + stats) are light. Hot numerics, if the
net engine needs them, go through NIFs (faber-tweann's existing path). The whole
harness can be BEAM-native and sovereign, which is on-mission.

## The pilot, restated (local modules, service-shaped API)

The pilot (003) is one BEAM node, three modules behind the API the services would
later expose:
- **world** (frozen mode): the seeded non-stationary generator.
- **referee** (pure module): scores the control arms sequentially — identical
  stream per seed, so pairing holds — computes the metric and the achievable-error
  reference, estimates variance to fix `N`. No verdict logic yet (no C).
- **contestant** in control configs only (A/B/D/E) — none need the unresolved hard
  parts (inject-into-a-net, the kernel-owned encoder). C comes after the pilot
  validates the apparatus.

Same module boundaries as the eventual services, so lifting it onto the mesh later
is a transport change, not a rewrite.

## Ties back

- 003: the referee *is* the pre-registration; arms are contestants; the pilot uses
  control contestants only.
- 004: the contestant is where the kernel contract lives; the engine swap is a
  contestant swap; the inject asymmetry means the net-engine contestant must be
  co-evolved in-process before it enters the league.

## What Fable's red-team changed (round 5)

The verdict: **a good federation story, a premature science story, and — run
naively over the mesh — actively destructive to the statistics.** Folded in:

- **Two trust domains, not three.** The referee's answer key *is* the world's
  schedule, and `e*_r` is fit on the world's generator, so world and
  referee are inevitably one trust domain. The only load-bearing boundary in the
  falsification phase is **{contestant} vs {everything else}**. Three services is a
  fine *deployment topology* for the league later; it is not three trust domains.
- **Integrity is reproducibility, not isolation.** A signed registry protecting
  *mutable* scoring code is security theatre. The fix: the pre-registration hash
  covers the **scoring code and the reference-predictor (`e*_r`) code**, and scoring
  is a deterministic pure function of (schedule, predictions). Anyone replays the
  verdict from frozen artifacts; a quietly-amending scorer is caught by replay.
  Replay-determinism is a stronger integrity mechanism than service isolation at a
  tenth of the cost. We reached for topology when we needed referential
  transparency.
- **The mesh breaks the pairing — the sharpest catch.** 003's power rests on
  *paired* comparisons: every arm sees the *identical* observation sequence per
  seed. Async delivery with deadlines and drops means arms experience *different*
  effective streams (one arm's late prediction becomes a penalty step, another's
  does not), which un-pairs the statistics and silently voids the power calculation.
  Local sequential execution gives pairing for free. **This is why the pilot must
  not run over the mesh.**
- **Predict-ahead needs a specified timing contract** (only if/when distributed):
  missing/late = scored at a penalty no better than the naive baseline's worst
  case (never skipped, or selective silence prunes hard steps); first-commit-wins,
  signed, deduped per (contestant, step); outcome revealed only after the deadline.
  Ugly consequence: the deadline must exceed the slowest engine (colibri 2-4
  min/step), so a distributed run is hostage to the mesh contract. Another vote for
  local-first.
- **Falsification = a CLOSED league**, all arms authored by us, no competitive
  entry. An open, competitive league Goodharts *upward* (gaming the metric shows up
  as excellent scores, which the validity floor passes silently), so it is a
  different instrument for a different question (open-ended selection), explicitly
  not pre-registered science.
- **Concession to state in the pre-registration:** co-evolving a net requires an
  inner-loop fitness signal, so the contestant embeds a replica of the generator
  *family* and a clone of the scorer. Therefore the **generator family is public;
  only the seed and schedule are secret.** Otherwise a critic says the contestant
  trained on the test distribution.
- **Later-league hazard:** sybil entries. Signed identity, one entry per principal,
  or self-play pumps the rankings. A next-year problem.

## Decision: local-first, services later

**Home + names.** The harness gets its own repo, **`hecate-arena`** (it is meant to
become its own services and to host others' contestants later, so it should not
live inside hecate-spartan). The three roles are **world / referee / contestant**
(the operator's naming, kept over challenger/arbiter/challenged). As services later:
`hecate-world`, `hecate-referee`; the contestant is a Spartan (hecate-spartan in
contestant mode). hecate-spartan stays the mind; hecate-arena is where it is tested.

Build the pilot as a **single local process** (one BEAM node, one module per arm,
the referee as a **pure module behind the same API a service would later expose**).
Publish the signed pre-registration **as a file in the repo** (a hash over the
schedule generator + scoring code + `e*_r` code) — no mesh required for integrity.
Keep this note as the *deployment* design for the league/federation phase, and
build the module boundaries to match it, so nothing is rebuilt when it is lifted
onto the mesh. **Distribute only once there is a number worth defending in public.**

Blunt, and correct: this was round three of building the courtroom before the
defendant exists. The kernel has still never once been asked to earn its keep. The
next thing that happens is the pilot, local, producing a number.
