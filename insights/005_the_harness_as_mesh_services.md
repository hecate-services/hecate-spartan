# 005 — The experiment as three mesh services

**Status:** DRAFT, going to Fable for red-team. Origin: the operator's proposal to
translate the whole program (003 metric, 004 contract) into hecate-om services —
an experimenting harness of **hecate-challenger / hecate-arbiter /
hecate-challenged**, where the challenged is a Spartan. This note argues it is the
right shape, with three refinements, and that it incidentally solves problems 001
left open.

## ELI5

Split the experiment into three players so nobody can cheat:
- a **world** that sets the puzzles (challenger),
- a **referee** that keeps the scorecard and the sealed answer key (arbiter),
- the **contestant** being tested (challenged, which is a Spartan).

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
| **hecate-challenger** | the sensor stream + the hidden regime schedule | the world |
| **hecate-arbiter** | the frozen pre-registration, the answer key, `e*_r`, the arms, the metrics, the kill thresholds | the neutral referee + registrar |
| **hecate-challenged** | a kernel + engine (the 004 contract) | the Spartan under test |

The arms of 003 (A/B/D/E and C) are simply **different challenged configurations**
facing the same challenger, scored by the same arbiter. Swapping the engine
(LLM vs net) is swapping a challenged. Nothing else moves.

## Three refinements

**1. The arbiter publishes a signed, tamper-evident pre-registration.** It holds
the frozen metric, `e*_r` (from separate genie rollouts), the arm definitions, the
kill thresholds, the changepoint labels, and the ground-truth outcomes — none of
which the challenged can read. Before a run it publishes the pre-registration as a
signed mesh fact (content-addressed, so it cannot be edited after the fact); after
the run it publishes the result against that same hash. This is how "frozen before
the run, no peeking" becomes *auditable* in a sovereign way, and it is the public,
compounding track record 001 said the society lacked — now a real artifact.

**2. The challenger has two modes, never mixed.**
- **Frozen** (seeded, pre-registered) for the falsification experiments (001-004).
  Determinism is the point; the generator family is frozen before the retrieval key.
- **Adaptive / co-evolving** for the open-endedness phase later (a POET-style world
  that probes the challenged's weaknesses, generates deceptive regimes, escalates).
  This is where open-endedness actually lives — but it *breaks* pre-registration, so
  it is a different mode for a different question. Same service, a mode flag, never
  both in one experiment.

**3. The mesh is the OUTER loop only.** Predict-*ahead* per step over the mesh is
fine for a falsification run (thousands of steps): the challenged commits its
prediction for `t+1` at time `t`, the arbiter scores it when `t+1` arrives — no
barrier, no way to peek. **But neuroevolution needs millions of cheap rollouts, and
those cannot go over the mesh** (latency would make it geologic). So the evolution
*inner loop* stays **in-process inside the challenged**; the mesh harness only
challenges, scores, and ranks *finished* challengeds. Mesh = tournament substrate;
in-process = training. Conflating them would be a fatal performance mistake.

## What it unlocks (the part that is better than expected)

Once arms are challengeds and the arbiter ranks them, you have a **league**: many
challengeds (different arms, engines, kernels, and eventually different people's
Spartans on their own nodes) all facing one challenger, ranked by one neutral
referee, with a signed public record. That is, at once:
- **selection** — the good rise, the bad are culled (001's missing pressure),
- **accumulation** — the track record is the compounding artifact (001's missing
  memory),
- **division of labour** — world / referee / contestant are genuinely different
  jobs (001's missing structure),
- **federation** — sovereign, mesh-native, anyone can enter a challenged.

So the operator's three-service instinct is not just an implementation of the
experiment; it is the concrete form of the "society with stakes" that 001 could
only gesture at. The society was never N chatbots in a room; it is N contestants in
a league with a real referee.

## It also resolves the language question toward BEAM

003 left open a Python-vs-BEAM tension. hecate-om pushes the answer to BEAM, and
that is now viable rather than dogmatic: Gene Sher's neuroevolution lineage (DXNN)
*is* Erlang, and faber-tweann is the natural net-engine challenged. The challenger
(a seeded generator) and arbiter (scoring + stats) are light. Hot numerics, if the
net engine needs them, go through NIFs (faber-tweann's existing path). The whole
harness can be BEAM-native and sovereign, which is on-mission.

## The pilot, restated as services

The pilot (003) is now concrete and small:
- **hecate-challenger** in frozen mode: the seeded non-stationary generator.
- **hecate-arbiter**: scores the control arms (A, B, D, E), computes the metric and
  the achievable-error reference, estimates variance to fix `N`. It does *not* yet
  need the kill-threshold verdict logic (no C yet).
- **hecate-challenged** in control configs only (A/B/D/E) — none of which need the
  unresolved hard parts (inject-into-a-net, the kernel-owned encoder). C comes after
  the pilot validates the apparatus.

## Ties back

- 003: the arbiter *is* the pre-registration; arms are challengeds; the pilot uses
  control challengeds only.
- 004: the challenged is where the kernel contract lives; the engine swap is a
  challenged swap; the inject asymmetry means the net-engine challenged must be
  co-evolved in-process before it enters the league.

## Open for Fable

1. Is three services the right cut, or is the arbiter secretly two jobs (registrar
   vs scorer) that should be split so the scorer can't quietly change the registry?
2. Predict-ahead over the mesh: does async delivery (a late/dropped prediction)
   create a scoring ambiguity a challenged could exploit (e.g., strategically
   "dropping" hard steps)?
3. Does making it a league invite Goodhart — challengeds that game the arbiter's
   specific metric rather than predict well — and does that show up as the
   validity floor failing, or silently?
4. Is "mesh = outer loop, evolution = in-process" a clean seam, or does the
   co-evolution-with-kernel requirement (004) drag the inner loop back onto the
   mesh anyway?
