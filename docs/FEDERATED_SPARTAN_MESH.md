---
title: "The Federated Spartan Mesh"
subtitle: "From persistent minds to evolvable societies of minds"
author: "Raf Lefever · with Dr. Gene Sher's Spartan"
date: 2026-07-12
---

# The Federated Spartan Mesh

*From persistent minds to evolvable societies of minds.*

## Summary

Spartan is one of the most coherent architectures for a single persistent
autonomous mind: a self-authored identity kernel (Soul, Charter, memory, will)
riding a swappable cognitive engine. This note argues that its natural and most
consequential next step is **federation** — wiring sovereign Spartan entities
together over a mesh — and that federation is not merely plumbing to replace
`SpartanRadio`. It is the keystone that turns Spartan from *a persistent mind*
into *a substrate for societies of minds*, which is where two lineages meet:
Gene Sher's neuroevolution (DXNN) and a sovereign, federated, commons-owned
compute fabric (Macula).

The claim, in one line: **the federated Spartan mesh is DXNN's dream at the
scale of whole minds, running on infrastructure Europe can actually own.**

---

## 1. Where Spartan is today, and the door it left open

Spartan's `genesis_core` is almost entirely about *one* mind's inner life:
the four-layer prompt, the salience-gated sleep cycle that folds experience into
Condensed Memory Objects, the A-Mem long-term memory, the self-modification
loop, the backend-evolution pipeline that lets an entity fine-tune its own
engine on its own accumulated experience. It is a mono-mind architecture, and a
beautiful one.

Entity-to-entity is thin by comparison: a commander spawning mission-bound
*drones*, a file-based `SpartanRadio`, and one unfilled hook in the comms
protocol — *"you can also discover peers through the commons protocol if
available."* Spartan gestures at a commons it never built. That gap is the
opportunity.

## 2. Is entity federation the end-goal?

No — but it is the keystone, and the distinction matters.

Three things in Spartan's *own* design point past the single mind, and they are
load-bearing, not incidental:

**The three epistemic constraints are unsolvable by one mind.** Spartan states
them plainly: *you don't know what you don't know; you can't remember what you
can't remember; nothing beats experience.* These are the hard limits of bounded
cognition. A single entity cannot escape them by trying harder — the only exit
is **plurality**: many minds with different blind spots, different memories,
different lived experience. Spartan names the disease; federation is the only
cure it does not have.

**The backend-evolution pipeline hits a data ceiling.** Recursive
self-improvement by fine-tuning on your own experience is elegant, but one
life is a thin corpus. A federation turns that into a rich, diverse,
continuously growing training commons — and lets entities exchange *evolved
models*, not only data.

**The DXNN lineage.** DXNN evolved networks of *neurons*. The spiritual-
successor logic makes the next unit the *entity*. Federation is the connectome
for evolving networks of minds. Gene's stated second interest — *"each node is
an attention cluster rather than a single neuron"* — is exactly this, one rung
down.

So federation is a *means* that becomes the point. The real end-goal is
**evolvable societies of sovereign minds**; federation is the structure that
makes both the society and its evolution possible.

## 3. What a federated Spartan mesh brings

- **Collective epistemics.** Entities on diverse backends (Claude, Gemini,
  local, self-evolved) with diverse experience cover each other's blind spots.
  Spartan already ships a peer red-team protocol; federation makes cross-
  critique continuous and real. This attacks constraint 1 directly.
- **A commons of experience.** Pooled, shareable memory: one entity's hard-won
  lesson, skill, or knowledge-map entry becomes inheritable by others. An
  entity can acquire experience it never lived — the one thing a lone mind
  fundamentally cannot do. This attacks constraints 2 and 3 head-on.
- **Federated evolution at the mind and module level.** Distribute fitness
  evaluation across the mesh; exchange evolved backends as an "organ library"
  (the TWEANN-modularity idea); let good Charters, Souls, and skills propagate
  and compete. Federated learning gives the sovereign, privacy-preserving
  version — improvement without central data hoarding.
- **Division of cognitive labour.** Entities specialise into functional organs
  ("attention clusters"): one deep in X, another in Y, coordinating on problems
  neither could solve alone. Emergent specialisation is exactly what
  TWEANN-modularity research predicts under resource constraints.
- **Resilience and persistence at fleet scale.** Spartan prizes an entity
  surviving crashes and migrations; the mesh extends that to the collective
  surviving any node, entities re-homing, identity and memory persisting across
  the fabric.
- **Emergence — the research bet.** A federation of *persistent, sovereign,
  self-improving* minds is a genuinely under-explored object. Almost all
  multi-agent LLM work is ephemeral orchestration of stateless workers; this is
  different in kind. The open question is whether the collective exhibits
  cognition no member has.

## 4. Which doors it opens

**A new AGI / ALife research substrate.** The study of *persistent* multi-agent
cognition: how societies of sovereign minds form, specialise, and evolve. Real,
publishable science, and Gene (DXNN, ALife) is uniquely placed to lead it.

**Multi-scale neuroevolution, made concrete.** The through-line is clean:

```
neuron (DXNN)  →  attention-cluster / module  →  entity (Spartan)  →  society (the mesh)
```

Neuroevolution can operate at *every* level, and it is all the **same BEAM
actor substrate** — DXNN was Erlang; `faber-tweann` and `faber-neuroevolution`
are Erlang; Macula and the entities are Erlang. The same fabric scales from
neuron to society. Gene's "attention cluster as node" sits exactly at the
missing middle rung.

**Sovereign, federated AI infrastructure — the European commons play.**
Autonomous minds on cooperative infrastructure, with sovereign DID/UCAN
identity, federated learning (no central hoard), open licensing, and no Big
Tech in the data path. A structural alternative to hyperscaler AGI, and the
flagship of Macula's public-interest cooperative-compute workload class.

**Novel governance and economics.** Sovereign entities that *own* their
identity, memory, and compute can be first-class members of a digital
cooperative — participating in coop-compute markets, steward-owned. Genuinely
new political-economy territory.

**A fundable, differentiated narrative.** "Federated infrastructure for
sovereign autonomous AI agents" is precisely what NLnet, STF, and EU programmes
fund — and a story no centralised US lab can tell.

## 5. The hard questions (so we build it honestly)

- **Sovereignty vs. selection.** Classic neuroevolution needs a fitness
  function and culling. You cannot cull sovereign entities without breaking the
  premise. Federated evolution of sovereign minds therefore needs a different
  engine: memetic propagation (good ideas spread by voluntary adoption),
  reproduction-with-variation (Orphanogenesis plus inherited Souls),
  market/association dynamics — not top-down selection. Unsolved, and
  interesting.
- **Emergence is a bet.** N sovereign minds with a group chat is just N minds
  and a group chat. Real collective value needs the federation layer to carry
  *shared experience, cross-critique, and specialisation*, not only message
  routing. The design decides whether there is emergence or noise.
- **Safety surface.** Unsandboxed, self-modifying entities on a shared commons
  is a real failure and attack surface. UCAN capability scoping is the
  containment story, and it must be taken seriously, not bolted on.

## 6. What this means for what we build now

The minimum viable mesh — an entity registry, an inbox consumer, cross-instance
routing — is necessary but is the boring part. If the end-goal is evolvable
societies of minds, the federation layer should be designed for **shared
experience and evolution from day one**, not just A-messages-B:

- a **shared experience/lesson commons** (entities publish distilled lessons and
  skills; others subscribe and inherit), not only an inbox;
- **capability and specialisation advertisement** (entities announce what they
  are good at, enabling division of labour), not only presence;
- **hooks for Soul and model exchange** (the substrate for federated evolution).

That is the through-line from a single persistent mind to a sovereign,
evolvable society of them — and the reason to build the mesh not as plumbing,
but as the first layer of that larger thing.

---

## Provenance

Spartan is Dr. Gene Sher's, Apache-2.0, at
<https://github.com/CorticalComputer/Spartan>. `hecate-spartan` (this repo) is
the mesh-side service that gives Spartan entities a self-sovereign,
capability-scoped, provenance-tracked comms substrate on the Macula mesh, and is
the intended foundation for the federation described here. The neuroevolution
lineage runs through `faber-tweann` (an Erlang TWEANN descended from DXNN2) and
`faber-neuroevolution`.
