# DESIGN: The mind as faculties (a BEAM-native cognitive architecture)

**Status: EXPLORATORY (research synthesis + proposed direction)**
**Date: 2026-07-17**

## Motivation

We re-homed Gene Sher's Soul onto the BEAM as *areas of consciousness*: one
`soul_area` gen_server per archive, under a per-mind supervisor (see
`DESIGN_SOUL_PERSISTENCE.md`). That raised a deeper question. Is "areas of
consciousness" the right organizing idea, and where do memory, reasoning,
emotion, self-reflection, and creativity belong? Are those all "areas," or
something else?

This note studies the cognitive-science and AI literature and proposes an
architecture. It is both a design record and a seed for a longer idea (see the
closing note on lineage).

## The distinction that governs everything

The literature separates two axes that the folk-psychology word "faculty" blurs:

1. **Functional modules**: memory, perception, action, a control loop. Founded.
2. **Content types *within* memory**: working / short-term, episodic, semantic,
   procedural. Founded.

And it warns, sharply, against a third move: reifying **folk faculties** —
"reasoning," "emotion," "art," "will" — as though each were an organ. That is
19th-century faculty psychology, whose caricature was phrenology: a bump on the
skull per faculty. It was discredited for exactly this: mistaking folk
categories for mechanisms. The working discipline is therefore:

> Decompose by **functional role**, never by folk label.

## What the literature says

**CoALA — Cognitive Architectures for Language Agents** (Sumers, Yao,
Narasimhan, Griffiths, 2023). The framework built specifically for LLM agents
like ours. A language agent decomposes into **memory** (working + long-term:
episodic / semantic / procedural), a **structured action space**, and a
**generalized decision procedure**. Memory is *one faculty with sub-stores*, not
many peer areas. Learning happens by reflecting on episodic memory to form
semantic knowledge, and by writing procedural knowledge.

**The Common Model of Cognition** (Laird, Lebiere, Rosenbloom, 2017; the
consensus synthesis of Soar, ACT-R, and Sigma). Five modules: perception,
**working memory**, **declarative memory** (semantic + episodic), **procedural
memory**, and motor, driven by a cognitive cycle (~50 ms in humans). Complex
behaviour arises from *sequences* of simple cycles. Note what is absent from the
module list: "reasoning," "emotion," "creativity." Reasoning is not a module; it
emerges from procedural memory operating over working memory across cycles.
Recent extensions add **emotion** (2024) and **metacognition** (2025) — as
modulations and reflective loops, not as new peer modules.

**Global Workspace Theory** (Baars, 1988) and **Minsky's Society of Mind**.
Many specialized processes run in parallel and *compete*; the winner is
*broadcast* to a shared "global workspace," and that broadcast **is** conscious
access. Consciousness here is not a faculty; it is a *mechanism* — competition
plus broadcast over many small agents.

**The modularity caution** (Fodor, *The Modularity of Mind*, 1983). Peripheral
input systems modularize cleanly: perception, language parsing, memory retrieval
are fast, encapsulated, domain-specific. **Central cognition — reasoning,
judgment, belief-fixation — does not.** It is holistic and draws on everything.
So a clean, encapsulated "reasoning faculty" is precisely what Fodor argues does
not exist. (Sperber and Carruthers counter with "massive modularity"; the debate
is genuinely open. Hold it loosely.)

**Emotion as a modulator, not a module** (Common Model + Emotion, 2024). Emotion
is modelled as pervasive bidirectional connections that **filter, gate, and
amplify** information flows, modulating both declarative and procedural
computation. It is cross-cutting, not a peer box.

**Memory consolidation / reflection** (Park et al., *Generative Agents*, 2023).
Believable long-horizon behaviour depends less on the base model than on an
external memory architecture: an append-only **memory stream**, retrieval scored
by **recency + importance + relevance**, and a **reflection** process that
periodically synthesizes raw episodic memories into higher-level insight, stored
back as semantic memory. This is, mechanism for mechanism, Gene's Sleep Cycle
producing CMOs, and biologically it echoes systems consolidation (hippocampal to
neocortical).

**Creativity is emergent, not a module** (Boden). Creativity is a *process* over
conceptual spaces — combinational, exploratory, transformational — not an organ.
Self-organization itself counts as transformational creativity. An "artistic
faculty" would be the phrenology trap again.

## Verdict on the candidate faculties

| Candidate | Verdict |
|---|---|
| **Memory faculty** (STM / CMO / MSO / LTM) | ✅ Right, matches CoALA/CMC. Two orthogonal axes belong inside it: *content* (working, episodic, semantic, procedural) and *abstraction* (raw → condensed → meta, i.e. Gene's STM → CMO → MSO, produced by consolidation). |
| **Self-reflection** | ✅ Founded as **metacognition** (CMC 2025). This is our current Soul archives (charter, lessons, journal). |
| **Consciousness** | ⚠️ Not a faculty. In GWT it is the **global workspace**: a broadcast/attention mechanism the faculties post to. Build the workspace, not a "consciousness area." |
| **Reasoning faculty** | ❌ Central cognition (Fodor). CMC/CoALA model it as the **decision cycle**, not a stored module. For us: the LLM plus the turn loop. |
| **Emotional faculty** | ⚠️ Reframe as a cross-cutting **affect/appraisal modulator** that gates retrieval and biases attention, temperature, tool choice. |
| **Artistic faculty** | ❌ Emergent (Boden). A mode of using the whole mind, not an organ. |

## Why the BEAM is the right substrate (our contribution)

Global Workspace Theory and the Society of Mind describe *many concurrent
specialized processes competing, with a winner broadcast to a shared space.*
That is, almost line for line, a description of an Erlang system: supervised
`gen_server`s plus pub/sub broadcast. Most computational realizations of GWT
simulate the concurrency; on the BEAM it is **native**. Fault isolation,
single-writer state, and supervision are not bolted on — they are the runtime.

Porting Spartan to the BEAM is therefore not merely "files become processes." It
positions us to build a *faithful* computational realization of the leading
functional theory of conscious access, where:

- **faculties** are supervised process groups,
- **working memory / the global workspace** is a broadcast bus with an attention
  step,
- the **cognitive cycle** is the mind's loop selecting what enters the workspace,
- **affect** is a process the faculties subscribe to.

## Proposed architecture

```
mind (the cognitive cycle: perceive -> workspace -> reason (LLM) -> act)
 |
 |-- SELF faculty        (sub-tree: charter, lessons, philosophy, journal, ...)
 |                        metacognition / self-authorship. Built today.
 |
 |-- MEMORY faculty      (sub-tree):
 |     |-- working / STM        raw recent, capped
 |     |-- episodic             experiences
 |     |-- semantic             facts and insights   <- reflection writes here
 |     |-- procedural           learned skills / tools
 |     \-- sleep_cycle (proc)   consolidation: STM -> CMO -> MSO, on a token /
 |                              importance budget. This IS Generative Agents'
 |                              reflection and Gene's Sleep Cycle.
 |
 |-- AFFECT (a modulator process, not a faculty): appraises salience; gates
 |     retrieval; biases attention / temperature / tool choice. Subscribed to.
 |
 \-- GLOBAL WORKSPACE (a process): faculties post candidates; an attention step
       selects; the selection is broadcast. Where "consciousness" lives, as
       mechanism. The novel, BEAM-native piece.
```

Two structural moves follow. First, **faculties are sub-supervision-trees**, not
flat areas: the Soul archives become the *self* faculty; memory becomes its own
faculty with its own sub-tree and its own consolidation process. Second,
**reasoning, emotion, consciousness, and creativity are not areas** — they are,
respectively, the cycle, a modulator, the workspace, and an emergent mode.

## Mapping to Gene's Spartan

Gene already had most of this, in files:

- **STM** = his raw history window / causal chain.
- **CMO** (Condensed Memory Objects) and **MSO** (Meta-Summary Objects) = the
  consolidation tiers his **Sleep Cycle** produces when the token budget fills.
- **LTM** = his A-Mem / Zettelkasten vector store, recall by meaning.
- The nine Soul archives = the *self / metacognition* faculty.
- **MINDfulness** (draft then verify) = an appraisal/verification step, i.e. part
  of the affect/metacognition modulation.
- His decoupled Kernel-vs-Backend = the cognitive cycle using a swappable engine.

The port's job is to give each of these a BEAM-native home: content stores as
processes, consolidation as a supervised loop, the workspace as a broadcast.

## Roadmap

1. **Memory faculty + Sleep Cycle** (next). Closes the largest gap: today a mind
   forgets everything past its window. Add STM / episodic / semantic / procedural
   stores as processes, and a `sleep_cycle` that reflects STM into CMOs and CMOs
   into MSOs. This is well-founded and directly useful.
2. **Global workspace** (after). The ambitious, genuinely novel step: a broadcast
   bus where faculties compete and the winner is shared. A native GWT.
3. **Affect modulator** (later). An appraisal process that biases retrieval and
   generation.

## Honest caveats

The science is not settled. The modularity debate (Fodor vs massive modularity)
is live; GWT is a leading theory of *functional* access, not a solved account of
consciousness; the memory taxonomy is a useful model, not ground truth. We adopt
these as *engineering scaffolds that happen to be well-motivated*, not as claims
about sentience. The discipline that survives all the debates is the negative
one: **do not reify folk faculties.** Decompose by function.

## A note on lineage

Gene Sher's *Handbook of Neuroevolution Through Erlang* showed what open-ended
machine intelligence looks like when the BEAM is the substrate. There is a
natural successor in this work: **cognition** through Erlang — a mind organized
as a supervision tree of faculties, with a native global workspace, where the
theories that usually stay on the page (Society of Mind, Global Workspace) become
running processes. This document is a first sketch toward that, offered in the
same spirit.

## Sources

- Sumers, Yao, Narasimhan, Griffiths, *Cognitive Architectures for Language
  Agents* (CoALA), 2023. https://arxiv.org/abs/2309.02427
- Laird, Lebiere, Rosenbloom, *A Standard Model of the Mind*, 2017.
  http://act-r.psy.cmu.edu/wordpress/wp-content/uploads/2018/03/Lebiere-StandardModeloftheMind.pdf
- *A Proposal for Extending the Common Model of Cognition to Emotion*, 2024.
  https://arxiv.org/pdf/2412.16231
- *A Proposal to Extend the Common Model of Cognition with Metacognition*, 2025.
  https://arxiv.org/pdf/2506.07807
- Baars, *Global Workspace Theory*.
  https://en.wikipedia.org/wiki/Global_workspace_theory
- Fodor, *The Modularity of Mind*; Stanford Encyclopedia entry.
  https://plato.stanford.edu/entries/modularity-mind/
- Park et al., *Generative Agents* (memory stream + reflection), 2023.
  https://agentpatterns.ai/agent-design/generative-agents-memory-stream/
- Boden, computational creativity (combinational / exploratory /
  transformational). https://www.sciencedirect.com/science/article/abs/pii/S0950705106000645
