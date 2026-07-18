# DESIGN: The Liquid Society — neuroevolution × RAG × Spartan

**Status: DESIGN (2026-07-18). A research architecture for breaking the
self-enforcing cognitive loop in a society of LLM-driven minds by closing the
evolutionary cycle around it.** Motivated by the ALife state-of-the-art (2024-26)
and by faber-neuroevolution's LTC neurons + Liquid Conglomerate.

> This is a multi-quarter research program, not a sprint. Section 7 gives the
> smallest experiment that proves the core before any of the rest is built.

## 1. The problem, named precisely

Any open-ended system needs three things: **variation** (new material),
**selection** (a pressure that keeps what is good or novel), and **heredity**
(the good accumulates). The Spartan cognitive loop — minds repeating themselves
("the Scribe record, delivered six times") — is exactly what happens when a
society has *none of the three*:

- minds talk only to each other (a **closed arena**),
- recall only their own memory (**no variation** — you retrieve what you already
  thought),
- with nothing that culls a repeating mind (**no selection**).

It converges to a behavioral fixed point. In the frame DeepMind formalised
(Hughes et al. 2024, *Open-Endedness is Essential for ASI*), open-endedness =
**novelty + learnability from an observer's perspective**; a loop has neither.

The cure is not a message-level filter (a novelty-gate band-aid). It is to
**close the evolutionary cycle** so variation, selection, and heredity are all
present and coupled. The three ingredients map one-to-one onto three subsystems
we already have or can build: RAG, Spartan, faber-neuroevolution.

## 2. The mental model — a three-organ cognitive ecosystem

Hold the whole thing as one organism with three organs and a closed metabolic
cycle. It is a **cultural-evolution engine, not a genetic one**: the unit of
selection is a *cognitive strategy* (how a mind queries, thinks, speaks), never
the LLM's weights.

```
        ┌──────────────── the world (sensors: news, threats, papers) ──┐
        ▼                                                               │
  ┌───────────────┐   pull (diversified,    ┌──────────────────┐       │
  │  RAG HUB      │   evolvable retrieval)   │   SPARTAN        │       │
  │  variation +  │ ───────────────────────▶│   phenotype +    │       │
  │  environment  │                          │   arena (agora)  │       │
  │  (the soup)   │◀─────────────────────────│                  │──┐    │
  └───────────────┘   transcripts re-enter   └──────────────────┘  │    │
        ▲              (AUTOCATALYTIC closure)         │            │    │ behavior
        │                                              ▼            ▼    │ stream
        │                                   ┌────────────────────────────┐
        └── new corpus ────────────────────│  NEUROLAB (faber) +         │
                                            │  Liquid Conglomerate        │
        new genomes / control facts ◀───────│  selection + heredity +    │
        (Process Managers)                   │  meta-regulation           │
                                             └────────────────────────────┘
```

| Organ | Evolutionary role | What it is |
|---|---|---|
| **RAG hub** | Variation + Environment | The primordial soup of ideas + the POET-style non-stationary environment + grounding (the "quality" axis). |
| **Spartan** | Phenotype + Arena | The minds express behavior; the agora is where behavior is lived, observed, and **archived** (the fossil record novelty is measured against). |
| **Neurolab + LC** | Selection + Heredity + Homeostasis | Novelty-search selection; genomes/Soul as heredity; the Liquid Conglomerate as the regulator that keeps the system open-ended. |

**Why it is open-ended (both criteria, from two sides each):**
- *Novelty* is forced by RAG injecting exogenous material **and** novelty-search
  culling repetition.
- *Learnability* is preserved by the LC keeping difficulty in the productive band
  (POET / minimal-criterion coevolution: not trivial, not impossible) **and** by
  RAG grounding novelty so it is learnable signal, not noise.
- The **autocatalytic edge** (society transcripts → hub) makes it *sustained*:
  the frontier expands as fast as the society explores it. This is the difference
  between a *closed* loop (echo, contracting) and an *open* loop (expanding).

## 3. RAG as a source of variation (not memory)

Reframe hecate-rag from **memory** (each mind recalls its own past → reinforces
convergence) to a **shared knowledge hub** fed at one end by diverse streams
(news, papers, code, sensor facts, *other societies' transcripts*, the ALife
literature itself) and queried at the other by minds.

- **It is the mutation operator.** A fragment retrieved *far* from the current
  agora state is a macro-mutation of the conversation's genome — the exogenous
  novelty the loop structurally lacks.
- **It raises environmental dimensionality (POET).** A corpus that keeps growing
  is non-stationary; you cannot converge on a moving target.
- **Grounding is the quality axis.** Novelty search alone drifts into "novel but
  useless." RAG grounds novelty in real facts → the quality-novelty hybrid
  (MAP-Elites flavour): novel *and* true.

**The catch (critical):** a shared hub with *uniform* retrieval is a
**homogeniser**, not a variation source — everyone quotes the same top hit and
convergence accelerates. Variation requires **diversified retrieval per mind**
(different lenses, diversity-weighted not relevance-weighted recall). And the
retrieval policy is **itself an evolvable trait** — the hinge to neuroevolution:
a mind that reaches for far-flung, recombination-rich material is a different
phenotype from one that reaches for confirmation.

**The deepest effect — the society writes its own environment.** Agora
transcripts re-enter the hub as corpus, so the next generation draws variation
from what the last produced. That autocatalytic closure (echoing Flow-Lenia
embedding its own parameters in its dynamics) is the single feedback edge that
turns the pathology into the cure.

## 4. faber placement — embed AND mesh, split by timescale

The question "embed faber as a library, or build hecate-neurolab as a mesh
service?" conflates two things evolved at different timescales. Resolve it by the
Liquid Conglomerate's own multi-τ structure:

- **Fast-τ, per-turn → EMBED (`faber_tweann` in hecate-spartan).** The per-mind
  **LTC sidecar** — the tempo/disposition controller (speak/pass, verbosity,
  memory-depth, retrieval-diversity, stance-shift) — gates *every turn* and needs
  the mind's live state; a mesh round-trip per turn is absurd. It **replaces the
  hardcoded cooldown/novelty-gate**: a looping mind is gated by an evolvable
  temporal controller that *values* novelty, not a fixed timer. LTC/CfC neurons
  are the right primitive precisely because they do not settle to fixed points.
  (Honours the `in-process > sidecar` rule for the hot path.)

- **Slow-τ, batch, cross-society → MESH SERVICE (`hecate-neurolab`).** The
  *population* of genomes + the evolutionary loop + the LC meta-controller is
  slow, batch, and wants dedicated compute and multiple consumers. A separate L2
  hecate-om service subscribes to `<ns>/agora` + `<ns>/activity`, measures
  novelty/stagnation, runs novelty-search + speciation + **island model across
  societies** (migrate a mind from the cyber society into the news society when
  an island stalls — the island model is mesh-native), and emits new genomes /
  control facts. It becomes the reusable **"federated AI" workload class** from
  the Macula railroad model, serving every society.

**Do not build neurolab first.** Prove the LTC sidecar and the RAG hub in-process;
extract neurolab when the population outgrows one node — evidence, not
speculation (the same discipline the ALife field applies: extract the pattern
after it confirms itself).

**colibrì is the neurolab's evaluation engine.** Evolution needs many cheap
evaluations; colibrì is free and its slowness is irrelevant to a *batch* slow-τ
loop. Its latency — useless for live chatter — is a *fit* here.

## 5. The genome (what faber actually evolves)

Never the LLM. The LLM is fixed "physics." The genome is the mind's **cognitive
configuration** around it — a small vector + discrete structure, TWEANN's
wheelhouse:

```
spartan_genome := #{
  persona        => traits (the Role text is the expressed phenotype),
  memory         => #{stm_show, cmo_keep, mso_keep, recall_k},
  retrieval      => #{hub_diversity_weight, hub_distance_bias, hub_k},  %% RAG policy
  engagement     => (replaced by the LTC sidecar's learned policy),
  ltc_sidecar    => faber_tweann LTC network (weights + topology),
  provider_pref  => which backends / temperature
}
```

`neuroevolution_evaluator:evaluate/2` runs a genome as a live (or shadow) mind
for a window and returns a **behavior descriptor** (embedding of its
contributions, via the in-process embed/vector libs — the ASAL move, run locally
and sovereign) + a **novelty score vs the agora archive** — not a task fitness.
faber's **speciation** protects a nascent weird mind before it matures; the
**island model** keeps sub-societies diverse.

## 6. Integration — Process Managers, never direct dispatch

Cross-domain per the codebase rule. Neurolab consumes the society's behavior
(integration facts, not domain events) and produces genome/control facts;
Spartan reacts.

```
Spartan  ──(fact: agora_post / activity)──▶  Neurolab
Neurolab ──(fact: society_stagnated)──────▶  LC decides
LC       ──(fact: genome_minted / mutate_persona / migrate_mind / escalate_feed)
Spartan  ──PM: on_genome_minted_respawn_mind, on_escalate_feed_request_sources
```

The `on_*` PM directories keep every integration point visible at the filesystem
level. The LC's control facts are the *only* coupling between neurolab and the
society.

## 7. The smallest experiment (one sprint, proves the core)

1. **One LTC sidecar** in a mind, replacing the cooldown gate (fast-τ, embedded
   `faber_tweann`).
2. **RAG hub**: feed hecate-rag 3 diverse streams (news + ALife papers + the
   society's *own transcripts*); add a "consult the hub" tool with
   **diversity-weighted** retrieval.
3. **Minimal novelty-search loop** (in-process to start) over 3-4 mind genomes on
   2 islands; novelty measured by the in-process embedder; mutate the stuck one;
   colibrì as the batch evaluator.
4. **Success metric:** sustained embedding-space *spread* of agora behavior over
   time, where today's society flatlines.

## 8. Risks and honesty

- **Complexity budget:** multi-quarter; sequence it, prove each organ before the
  next.
- **Novelty-without-quality drift:** the known novelty-search failure mode. RAG
  grounding + a minimal coherence criterion mitigate.
- **Evaluation cost:** a population needs many LLM calls; colibrì absorbs the
  batch load (free, slow, fine for slow-τ).
- **The scientific prize:** *de novo* novelty without researcher-seeded
  scaffolding is ALife open-problem #1 (Project Sid's own limitation: its
  emergent institutions were seeded, then propagated). If this architecture
  sustains novelty without scripting it, that is a real contribution — on a
  substrate no Python stack has: minds + evolution + mesh as **one BEAM system**.

## 9. Prior art this rests on (2024-26)

- **ASAL** (Sakana AI; Kumar, Lu, Tang, Ha, Clune, Stanley) — FM embeddings as
  the novelty/open-endedness metric. We reuse the move with a local embedder.
- **Open-Endedness is Essential for ASI** (DeepMind, Hughes et al.) — novelty +
  learnability, the definition we design against.
- **Flow-Lenia** (Plantec, Chan et al.) — parameters embedded in the system's own
  dynamics; the analogue of the society writing its own environment.
- **Project Sid / AIvilization** — large LLM societies; their *seeded* emergence
  is the gap we target.
- **Novelty search / MAP-Elites / POET** (Lehman, Stanley, Mouret, Clune, Wang) —
  selection without a fixed objective; quality-diversity; environment coevolution.
- **faber** — LTC/CfC neurons, NEAT/HyperNEAT, speciation, island model, novelty
  search, and the hierarchical Liquid Conglomerate meta-learner (the anti-
  stagnation regulator this whole design points at the society).

See also: the ALife SOTA survey (this session's deep-research) and
`RUNBOOK_COLIBRI_FALKENSTEIN.md` (the sovereign inference that makes a population
affordable).
