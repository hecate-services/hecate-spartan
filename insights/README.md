# insights — a research log for the Spartan substrate

These are not release notes or design specs. They are the thinking: the running
record of an open question we are still inside of. **What is Spartan actually a
substrate *for*, and how do we make its central claims falsifiable?**

The method here is deliberate: interrogate the architecture, find where it cannot
be measured or disproven, and redesign toward falsifiability. The conversations
that produced these notes (with the operator and with an independent model,
"Fable", used as an adversarial reviewer) are themselves part of the research, so
they are captured rather than summarised away.

**Convention: every note carries a short ELI5 section.** These ideas should be
legible to any curious human, not just the people building it. If a note cannot be
explained plainly, we do not understand it well enough yet.

## Log

| # | Note | Question it sits on |
|---|------|---------------------|
| [001](001_society_of_minds_is_not_n_chatbots.md) | A society of minds is not N chatbots | Why does the N-LLM agora converge to bland consensus, and what would make a collective more than the sum? |
| [002](002_what_backend_what_sensor.md) | What backend, what sensor? | What does an LLM actually bring as a Spartan engine, could an *evolvable* backend embody the thesis better, and do we need *numerical* sensors to make anything falsifiable? |
| [003](003_metric_and_kill_threshold.md) | The metric and the kill threshold | How do we judge whether the kernel earns its keep, with a number written down before we build, so this can't become endless reframing? |
| [004](004_engine_agnostic_kernel_contract.md) | The engine-agnostic kernel contract | What do "memory", "self-audit", "authorship", "continuity" mean when the engine is a net, not an LLM — and what honestly cannot port? |
| [005](005_the_harness_as_mesh_services.md) | The experiment as three mesh services | Can the whole program be a **world / referee / contestant** harness (its own `hecate-arena` repo), and does that turn "no peeking" from discipline into architecture (and into a league with real selection)? |
| [006](006_arm_c_kernel_and_inject.md) | Arm C: the kernel + inject | What does "inject retrieved memory into the engine" concretely mean for the pilot, and does arm C beat both the detector (D) and the raw memory (E)? |
| [007](007_experiment_1b_pre_registration.md) | Experiment 1b: a harder world | 1a failed (k-NN heaven); what pre-registered harder world (nonlinear, noisier, sparser, perturbed recurrence) would let a model beat lookup — decided before it runs? |
| [008](008_experiment_1b_result_and_the_arm_f_correction.md) | Experiment 1b: the result, and the arm-F correction | C lost 1b too — but does that kill the *kernel*, or just its *engine*? The missing control (arm F = engine alone) shows the faculties beat their own engine; the deficit is the engine class. |

## The one line, so far

We now have numbers that could go up, and a signed result that they did not — yet.
The kernel loses to raw lookup on both worlds (1a, 1b), but arm F (the engine alone)
shows the kernel faculties reliably beat *their own engine*: the deficit is the
engine class, not the machinery. The next question (1b-prime) is whether fixing the
engine and the match gate, in the same frozen world, grows that hair's-breadth
advantage into a real one — so the Spartan thesis (a sovereign kernel that improves
behaviour over time, on a swappable engine) stays an experiment, not a vibe.
