# 002 — What backend, what sensor?

**Status:** open research. This note ends with a pre-registered experiment and a
kill criterion, on purpose (see the last section on why).

## ELI5

An LLM is a brain that already knows a lot but never learns from living: its
knowledge is frozen the day it was trained. Spartan's big idea is that the brain
should be *swappable*, and eventually able to *evolve*. You cannot evolve a frozen
brain. To test evolving brains you need a scoreboard, and you cannot get a clean
scoreboard from opinions about the news, because words are mushy and rarely simply
right or wrong. You need **numbers** with right answers. And a mind that keeps a
memory only proves its worth when the world keeps **changing** (otherwise
remembering is pointless). So the plan: feed a mind a stream of numbers whose
hidden rules keep shifting, and measure who copes best. Practise in a cheap
simulator first, then move to real energy-grid data. The catch we found: the LLM's
one irreplaceable gift is *language itself*, which is the very material the Spartan
"self" is written in, so we cannot simply throw it away.

## The question

Round 1 ([001](001_society_of_minds_is_not_n_chatbots.md)) said: make speech
falsifiable. The operator then cut deeper:

> News is prose, and prose is a poor candidate for measurable, falsifiable
> outcomes. Right now the backend for a Spartan is an LLM. What does an LLM
> actually bring us? Could we come up with another *type* of backend on which the
> principles of Spartan can be tested, or even *evolved*? Can we change the sensor
> input, perhaps to something more numerical?

## Two Spartan claims, and they need separating

The mistake was treating "Spartan" as one thesis. It is two:
- **Continuity thesis:** a durable, self-authored "I" that persists across engine
  swaps and improves behaviour over time.
- **Evolvability thesis:** the engine is swappable, and the *native* swap (Gene
  Sher's own DXNN lineage) is a **neuroevolved** engine that adapts by variation
  and selection, not a frozen pre-trained one.

The LLM is a fine engine for the continuity thesis and the wrong engine for the
evolvability thesis. Separate them and the experiments design themselves.

## What an LLM actually brings (corrected)

An earlier draft called the LLM a "frozen oracle." Fable corrected two overclaims,
and the corrected version is the real picture:

1. **World-knowledge priors.** A mind that bootstraps in open domains with no
   training. Irrelevant on a numerical stream, so nothing is lost there by
   swapping it out.
2. **Language is not just the LLM's output; it is the medium the kernel is built
   from.** The nine-archive Soul, draft-then-verify self-audit, and self-authored
   reminders are *text operations*. A TWEANN cannot read its own Soul. Swap in a
   numerical engine and you have not replaced an organ, you have **amputated the
   self-authorship mechanism**, unless you redefine what authorship means for a
   non-linguistic engine. "My topology evolved" is not authorship; it is selection
   acting on you. So the kernel, as designed, needs language *somewhere*.
3. **"Frozen" is too strong.** In-context reasoning over retrieved memory *is*
   learning from the mind's own life: slow weights frozen, fast state plastic. The
   real, narrower limitation: **no compression of experience into the function
   itself.** The engine never gets better at its job; only the notes it is handed
   improve.

## Why numerical sensors, and the trap in that idea

Evolution needs fitness; fitness needs measurable outcomes; prose gives neither.
So: a numerical sensor stream, predict the next value(s), score by error. That is
the falsifiability the news framing lacked.

The trap Fable flagged: **on a *stationary* prediction task, the sovereign kernel
is almost certainly dead weight.** Persistent memory, self-audit and continuity
earn their keep only under **non-stationarity**: regime shifts, engine swaps
mid-life, retention across episodes. A stationary stream is just supervised
forecasting, and a stateless net will match or beat a kernel that is paying to
carry a Soul.

This turns a worry into a design rule: **build non-stationarity into the sensor on
purpose** (drifting regimes, seasonal structure, occasional shocks). It is also
exactly what open-endedness needs to avoid converging to a fixed optimum and
dying. One decision serves both. And it converts the kernel's vague promise into
concrete numbers:
- **recovery time after a distribution shift** (kernel-on should recover faster),
- **retention across an engine replacement** (kernel-on should keep more than a
  cold restart).

Those are the Spartan numbers. Without regime shifts we are testing nothing
Spartan.

## Is this just RL with extra steps?

At the task level, yes, and that is correct. The task should be boring and
standard; novelty in the *task* is where research hides from falsification. The
line between "a Spartan with an evolvable backend" and "a plain RL agent" is not
philosophical, it is an **ablation**: same task, kernel-on vs kernel-off. If the
kernel moves no number, it is dead weight *on that task*, and that is a finding
worth having.

## Sensor decision

- **First: a synthetic, non-stationary simulator.** Not close. Neuroevolution
  needs population × generations × evaluations, i.e. millions of cheap rollouts. A
  real feed gives one trajectory at 1× wall-clock; you cannot evolve against real
  time. Note the inversion: the compute wall with LLMs was expensive inference and
  no training; with TWEANN it is cheap inference and expensive search, so sim-first
  is what the new wall dictates.
- **Second: energy (Track A, OpenEMS/Victron).** On-mission, sovereign, genuinely
  non-stationary (weather, prices, behaviour), falsifiable via prediction and
  control error. The real target, once the machinery works in sim.
- **Out: mesh telemetry** (self-referential confounding: the mind's actions perturb
  its own sensor; low information density). **Out: markets** (off-mission,
  adversarial).

## The unglamorous core: an engine-agnostic kernel contract

The likely reason none of this is trivial: **the kernel-engine seam is probably a
lie in the code.** Spartan's backend-evolution phases exist on paper, but the
actual kernel API is almost certainly prompt-in / completion-out shaped. A
numerical net does not speak that. The real engineering research here is defining a
genuinely engine-agnostic contract: what does "memory" mean to a net? what is
"self-audit" for a non-linguistic engine? what is "self-authorship" when there is
no text? This is unglamorous and unavoidable, and it is where the actual novelty
lives, not in the task.

Related, and harder: with *continuous* evolution there is no discrete swap, so the
self must live **entirely in kernel state**. That is the sharpest possible test of
the sovereignty thesis, but only if measurable continuity is defined *before* the
run, else it is unfalsifiable vibes.

## The destination vs the first move

The destination is the hybrid **Liquid Conglomerate**: a fast evolvable numerical
actor (selected by fitness) + a slow LLM reflector (linguistic self-authorship,
meta-controlling the actor) + a Spartan kernel spanning both. It resolves the
language problem (the LLM keeps the authorship medium) and the evolvability problem
(the net adapts). But building it now would be a third straight session of
plumbing. **Isolate one variable at a time.**

## Pre-registered experiments (write the number before touching faber-tweann)

Round 2 is the second reframe in two rounds. Research without a pre-registered kill
criterion becomes serial reframing. So:

**Experiment 1 — does the kernel earn its keep?**
- Sensor: synthetic non-stationary stream (drifting regimes + shocks).
- Task: predict next value(s), scored by error.
- Engine: held constant (start with the cheapest that works; even a small net).
- Variable: **kernel-on vs kernel-off**, same engine, N seeds.
- Number: **steps to recover pre-shift error after a regime change.**
- Kill criterion (to finalise before running, proposed): if kernel-on does not
  recover meaningfully faster than kernel-off (proposed: ≥20% fewer steps, across
  seeds, significant), the kernel is dead weight on numerical prediction. That is a
  real finding; park or redesign the kernel contract, do not reframe the task.

**Experiment 2 — the swappable-engine thesis, made experimental.**
- Kernel held constant; harness identical to Experiment 1.
- Variable: **LLM engine vs evolved-TWEANN engine.**
- Number: score on the same non-stationary task + retention across a mid-life
  engine swap.
- This is the head-to-head that the whole "swappable engine" claim rests on. Do
  not run it until Experiment 1 has given the kernel a number.

Only after both components separately earn a number does the hybrid get built.

## What is explicitly parked

The N-mind news agora. It is depth-first from here: one kernel, one sensor, one
number, before any society is run again.
