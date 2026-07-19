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
| [009](009_experiment_1b_prime_pre_registration.md) | Experiment 1b-prime: fix the contestant, not the world | Same frozen world; give arm C a rule-tuned engine, a strict rule-derived match gate, and a level-including reset — does the kernel now beat lookup? Fable-cleared (round 9) before building. |
| [010](010_experiment_1b_prime_result_and_the_instrument_failure.md) | Experiment 1b-prime: a first positive, and an instrument failure | Engine+reset finally beat lookup (first C-over-E win) — but a units error in the precision guard gagged inject to 2 firings, so *memory* went untested. Signed partial + pre-registered instrument repair. |
| [011](011_the_signed_negative_memory_is_falsified.md) | The signed negative: memory is falsified | Repaired, inject fired 507× and added nothing; a 100%-precision oracle is *reliably worse* than engine+reset. Restoration loses to restart under recurrence jitter. Thesis falsified; STOP. |
| [012](012_what_survives_the_substrate_after_the_kernel_dies.md) | What survives: the substrate after the kernel dies | Inject died, but retrieval (external, queried) was the winner all along — which IS a public commons. Reframe: external freshness-aware memory + a sovereign commons, not an improving kernel. |
| [013](013_the_scope_of_the_negative_and_the_frontier.md) | The scope of the negative, and the frontier | "Spartan is over" was an over-reach (a mood, not a measurement) — retracted. 011 kills *verbatim recall under drift*; abstraction-memory, learned dynamics, and present-tense faculties remain open. |
| [014](014_experiment_m1_self_audit_economics_pre_registration.md) | Experiment M1: self-audit economics (pre-reg) | Does draft+verify cut hallucination enough to justify 2× compute? Snippet-anchored mechanical checker, constant-free kill rule (delete more garbage than good), structural token ceiling, the first cost ledger. Fable-cleared (round 14), build-ready. |

## The one line, so far

One mechanism is signed dead (note 011): **verbatim** memory recall — replaying stored
past under drift — loses to forget-and-relearn, even with a perfect recognizer,
because the past returns changed. That kill is narrow and licensed to generalize along
its mechanism; it does **not** bury the program (note 013 retracts that over-reach).
Still open and untested: abstraction-memory (recall the shape, relearn the numbers),
memory as learned dynamics, and every faculty that reads the *present* rather than the
past — first of which, self-audit/mindfulness, is pre-registered as Experiment M1
(note 014), on a mechanically-checkable task, carrying the program's first cost ledger.
The method is the constant: a number, a kill threshold, and an adversary, before we
believe anything.
