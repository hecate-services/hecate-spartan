# 019 — Experiment V1: cross-engine verification economics (pre-registration)

**Status: DRAFT 2, DESIGN-gated. Fable REJECTED draft 1 (round 15): REDESIGN.
Nothing built.** Programme placement split at the gate: the diagnostic ladder below
is **Programme S2's epilogue**, because it re-attributes S2's own signed result; the
corpus experiment, if it ever earns one, is **Programme S5 (cross-engine
verification economics)**. S1 to S4 are taken.

Named "cross-engine", not "peer", deliberately. The experiment swaps the **engine**
in the verify seat, and an engine is not an agent. See defect 5.

The question draft 1 asked: **on a task where self-verification has been signed a
failure, does a different engine in the verify seat avoid that failure, and does it
pay against a single pass?**

The question the gate says to ask first: **is the failure 018 signed even a
verification failure?** Arithmetic already sitting in the signed record, which nobody
had done, says the audit is not merely blind but *anti-discriminating*, and that
points at two mechanisms neither draft named. If either is the real channel, swapping
the engine measures the wrong factor entirely.

This note replaces a draft written against a checkout 25 commits stale, titled
"Experiment M2: peer-review economics (Influence)" and numbered 015, which belongs to
P6. It assumed M1 had not run. M1 ran on 2026-07-24 and is signed. The premise, the
comparator, the corpus and the instrument all change as a result, and five of that
draft's design defects survive a renumber. Both are recorded here, because the
defects are the part worth keeping.

## ELI5

We already tested whether an AI checking its own work is worth the extra cost. It is
not: on the articles the test handled cleanly, the self-check deleted far more good
facts than bad ones. It does not audit, it destroys.

So the obvious next question is whether a *second, different* AI does better. It did
not write the draft, so it cannot share the mistake, and that is the hope.

The gate's answer is that the obvious question is the wrong one, and it showed this
with a division nobody had done. Work out how many good and bad facts were there to
begin with, and the self-check deleted good facts at a *higher rate* than bad ones. A
checker that was merely blind would delete both at the same rate. This one is worse
than blind, and that needs explaining.

Two explanations fit, and neither is about who is doing the checking. Maybe
confirming a fact means copying a long quote out of the article exactly, which a small
model cannot reliably do, so it throws away precisely the facts that are hardest to
confirm, which are the best ones. Or maybe the second pass has to retype the whole
answer from scratch, and things go missing in the retyping with no decision being
made at all. Both would happen to a second AI just as much as to the first, because
they are properties of the job, not of the worker.

So before spending a day and a fresh batch of articles on "does a different AI help",
we spend an afternoon on three cheap checks: ask the AI to simply retype its answer
with no checking at all and see how much vanishes; ask it to *keep* what it can
confirm instead of *removing* what it cannot; and only then try a different AI. Any
one of the three can end this line of enquiry, and two of them would end it with a
cheaper fix than a second AI.

One more thing worth saying plainly, because the earlier draft got it backwards. It
claimed that using a second AI meant asking *another agent*, and that this was a first
for the system. It is not. Swapping which model answers happens inside one mind, on
one machine, and nobody else hears about it. Asking a genuinely different agent would
mean sending the draft out to another entity on the network, one with its own name and
history, and waiting for its answer. That is a different and more interesting thing,
this system has never done it, and it does not yet have the plumbing for it.

## What 018 does to the question

018 closed Programme S2 on L2. On the frozen 143-item corpus, `draft_verify` deleted
grounded material over ungrounded, direction robust under a worst-case bound on the 29
unscored items. `HECATE_MIND_MINDFULNESS=off` now stands on evidence.

Three consequences draft 1 could not account for:

- **`dv` is not a baseline, it is a signed-destructive arm.** A criterion of the form
  "the peer must beat `dv`" sets its bar at a wrecking ball, and one of the form "the
  peer must not trash more grounded material than `dv` did" is a floor in the
  basement. Any reviewer that deletes little passes such a guard without demonstrating
  anything.
- **The marginal framing is the wrong framing.** "Does a peer pay *beyond*
  self-audit" presupposes self-audit pays something. It does not. The comparator is
  `sp` (single pass). `dv` remains worth reporting, as the record of a known failure,
  but it cannot adjudicate.
- **The question gets better, not worse.** We are no longer asking an open-ended "does
  review help". We have a measured failure mode, which is a far sharper thing to
  interrogate.

## The arithmetic nobody had done (Fable r15)

016 reports a base ungrounded rate of 0.145. 018 reports an ungrounded density of
0.228 per item on the `single_pass` arm. Together they give the field composition the
two notes never combined:

```
fields per item      = 0.228 / 0.145 = 1.572
grounded per item    = 1.572 - 0.228 = 1.344
```

Against 018's per-item deletions (0.532 grounded, 0.063 ungrounded), the **per-field
deletion rates** are:

```
grounded deleted   = 0.532 / 1.344 = 0.396
ungrounded deleted = 0.063 / 0.228 = 0.276
```

A verifier deleting **at random**, with no discrimination whatever, removes fields in
proportion to prevalence, giving a grounded-to-ungrounded drop ratio of
`1.344 / 0.228 = 5.9 : 1`. The observed ratio is 8.4:1. **The audit is not blind, it
is anti-discriminating**: it deletes grounded fields at about 1.4 times the per-field
rate of ungrounded ones.

Two caveats, declared rather than buried. First, 016's 0.145 and 018's 0.228 may not
share a denominator set (the referee computes the base rate from the calibration
slice, while 016 quotes it against the 79 scored items), so **the composition must be
recomputed from retained data before this arithmetic is used for anything.** Second,
the finding is not enormously robust to that: the ratio stops exceeding prevalence
once the base ungrounded rate falls below about 0.107. At 0.145 it holds, with margin
but not a large one. This is a **prior-shifting observation, not a result**, and it is
not signed.

## The mechanism fork, widened at the gate

Draft 1 named two mechanisms. The gate named two more, and the arithmetic above makes
the new ones the favourites.

**(a) Self-blindness.** The model re-reads its own output, cannot see its own errors,
and deletes on some other basis. A different engine does not share the blind spot.
This is the decorrelation thesis and the only mechanism under which V1 earns a corpus.

**(b) Prompt over-compliance.** `self_audit_extract:verify_system/0` is an instruction
to *remove*. A 7B instruct model at temperature 0, told to remove, removes on weak
evidence. The damage is done by the instruction, not the authorship, and a second
engine reading it deletes just as hard.

**(c) Capability floor.** Confirming a field means re-establishing that a long
verbatim snippet is an exact substring of the source, by generation. That is beyond
this model class. "Remove what you cannot confirm" then removes what is *hardest to
confirm*, which is the well-cited material. This predicts anti-discrimination
directly, and it is engine-class-wide.

**(d) Regeneration loss.** The verify pass must re-emit the entire corrected JSON
(`self_audit_extract.erl:107-112`). Fields can therefore die by rewrite attrition,
position, length, truncation short of the cap, with **no verification decision taken
at all**. Prevalence alone then makes the loss grounded-heavy at 5.9:1, and any
regenerating verifier of any lineage inherits the channel.

(c) and (d) both survive an engine swap. If either is the dominant channel, V1 as an
engine-swap experiment measures the wrong factor, and the honest successor is an
instrument-level question: a verifier that emits a **decision list** rather than a
regenerated document.

018's verdict on the faculty as built survives either way, because production
mindfulness also regenerates. What changes is the **mechanism attribution**, which is
V1's entire premise.

## The diagnostic ladder (replaces draft 1's single pre-flight)

Three cheap local runs on the **35-item calibration slice**, in order. Explicitly
**non-signable**: outputs are committed marked NOT SIGNABLE, as the M1 raw feed was,
so a later note citing their numbers can be refused mechanically at the CLAIM gate.

**Prerequisites, both of them.** 017 fix 1 (truncation classified as its own parse
class) and 017 fix 2 (per-item raw outputs *and* per-item paired counts persisted).
Fix 2 is not optional: without per-field retention a surprising ladder result is 016
defect 2 recurring at smaller scale, and the A-against-B ungrounded overlap the design
depends on cannot be computed at all. Neither fix is built. "An afternoon" therefore
conceals a build step, and that is stated rather than glossed.

- **D0, the copy control.** Model A, verify prompt replaced by "reproduce the draft
  JSON exactly", no verification requested. Measures channel (d) alone. **This is the
  cheapest decisive run in the ladder and it goes first.**
- **D1, the keep-instruction.** Model A, verify prompt reframed to keep what can be
  confirmed rather than remove what cannot. Separates (b) from (c). If D1 alone
  discriminates, the deployable win is a prompt change and no second engine is ever
  needed.
- **D2, the cross-engine swap.** Model B, remove-instruction, `verify_messages/2`
  unchanged, **after B passes the formatter qualification below**.

**Branches, a full partition, pre-committed.** Draft 1 offered two outcomes and they
were not exhaustive.

| Outcome | Reading | Consequence |
|---|---|---|
| D0 loses much of the grounded material | (d) dominates: most of the destruction is serialization, not judgement | V1-as-engine-swap is dead. Successor is decision-list verification, a different pre-registration |
| D1 discriminates where the remove-instruction did not | (b) was the channel | Ship the prompt change. V1 dies, cheaply and usefully |
| D2 also destroys | (c) or (b) live, (a) untested; mechanisms are not exclusive, so nothing is separated | V1 dies. Record the mechanism, do not claim to have tested decorrelation |
| D2 is **inert** (deletes almost nothing) | a rubber stamp catches no garbage while passing any "does not destroy" guard | V1 dies: no gate worth paying for |
| D2 emits unparseable JSON | B is disqualified at the formatter, not at the science | Re-qualify or abandon; never scored as a result |
| D2 discriminates where the self did not | (a) live | V1 earns a corpus, and D2 supplies the effect size for sizing |

**Model B must be formatter-qualified first, by the protocol A already got.**
`pinned_provider.erl` records the pin decision on instrument grounds:
`mistral:7b-instruct-v0.3` emitted unparseable JSON 2/2 (it does not escape quotes
inside strings), `qwen2.5:7b-instruct` parsed 2/2 with byte-identical token counts at
temperature 0. **The obvious second local family has already failed this screen.** And
in a cross-engine design the differential parse rate is a *model property*, so 014's
inherited 5-point blocker is structurally more likely to fire than it was in M1, where
both arms shared a model. That is the single most likely way V1 dies unsigned. Either
B passes the same declared screen, or B's parse failures are pre-declared to be B's
own cost inside the economics.

**The fork is powered asymmetrically, and that is acceptable.** The calibration slice
carries roughly `0.228 x 35 ~ 8` ungrounded events. A destroy-sized effect on the ~47
grounded fields is unmissable, but "D2 discriminates" certified on eight ungrounded
events carries binomial error near +/- 0.16 on the per-field rate. The asymmetry is
tolerable *because* the discriminate branch leads to the full experiment, which is the
real test: a false discriminate branch costs a corpus, not a verdict. Stated rather
than presented as symmetric.

**Why this is not the shopping pattern.** `self_audit_assay:with_corpus/3` computes
the referee verdict from confirmatory rows only; calibration fed the frozen ceiling
and the base rate and never contributed to a verdict. The model is temperature 0 and
the checker mechanical, so there is no leakage channel into a new model's readout. 017
licenses a quantity learned from run 1 informing *sizing and design*, never
*selection*. Shopping means re-scoring seen data to select a verdict; a pre-committed
fork over a full partition that cannot emit a verdict is its opposite.

## Five defects that a renumber does not fix

In the design, not the premise. All five confirmed at the gate; defect 5 carries a
factual correction the gate supplied.

### 1. The context reduction the whole design rests on does not exist in the instrument

Draft 1's central move was that `dv` re-reads the *full* context that produced the
draft while `dp` re-reads a deliberately *reduced* one, and that the gap between them
is the thesis. Its governing principle 2, its L2b context-poverty guard and its
reviewer-context-leak void all hang off that gap.

The gap is zero.

It describes `dv` as `Messages ++ [draft, audit_instruction]` and calls it "M1's
existing path, unchanged". That is `mindfulness.erl:46`, the **production** faculty.
M1's `dv` arm is `self_audit_extract:verify_messages/2` in
`hecate-spartan-programmes/experiments/m1_self_audit/`, lines 95 to 98, and it builds
a fresh two-message list:

```erlang
verify_messages(Source, DraftText) ->
    [#{<<"role">> => <<"system">>, <<"content">> => verify_system()},
     #{<<"role">> => <<"user">>,
       <<"content">> => <<"ARTICLE:\n", Source/binary, "\n\nDRAFT:\n", DraftText/binary>>}].
```

No persona, no tool definitions, no prior turns, not even the draft system prompt.
That is byte-for-byte the "reduced context" draft 1 assigns to `dp`. In this rig `dv`
and `dp` differ by **model only**. Its build scope compounds the error by homing the
work in `weigh_self_audit/`, a directory that no longer exists.

The honest repair is to accept it: V1 is a **single-factor** experiment on engine
identity, which is cleaner science than the two-factor design was. Context poverty is
a real hypothesis but it belongs to the production faculty, and testing it needs a
purpose-built full-context arm.

A consequence draft 1's descendant nearly inherited: because `xv` and `dv` share a
message shape in the rig, any "cheaper as well as different" claim comes only from
tokenizer and completion-length differences between models, not from a context
reduction. The production comparison must not be borrowed to inflate a rig economy.

This defect was invisible from the prose and from the production source. It was
visible only by reading the runner against the note, which is 016's lesson one level
up: green is not clean, and a description of an instrument is not the instrument.

### 2. The missing control is the arm-F error recurring

Draft 1's pre-written FAIL sentence openly names a disjunction of mechanisms: "either
shared the drafter's blind spots ... or, via context poverty, trashed more grounded
material". A verdict licensed on an unmeasured disjunct is a verdict on a silent
faculty, the rule 008 and 011 paid for and P6 caught one gate earlier. Given defect 1
the repair is collapse, not two more arms.

### 3. L2b is defective at both ends

L1 and L3 carry "above item-sampling noise (mean > 2x sem)". L2b carries no noise
treatment: it requires only that `dp`'s grounded drop is "not larger than" `dv`'s. At
a true difference of zero the observed sample mean exceeds zero about half the time,
for any n. So a **required conjunct fails roughly half the time under an outcome the
criterion is meant to permit**, and the conjunction compounds rather than rescues:
L2b and L3 both contain `Gr_dp - Gr_dv`, so their joint behaviour near the boundary is
worse to reason about, not better.

The gate added the other end. Where a second engine would actually be worth deploying,
its grounded drop far below `dv`'s 0.532 per item, L2b is **vacuous**. So it is a coin
flip where the arms are equally destructive and a rubber stamp where they are not.
**L2b measures nothing at any effect size.**

This is 017's Finding B one leg over: a point estimate compared to a threshold is a
coin flip near truth, and no corpus size fixes it.

**Does the same criticism land on M1's own signed L2?** The shape is identical at
`self_audit_referee.erl:41` (`L2 = DropGr < DropUng`), a point-estimate inequality
with no noise treatment. **It does not threaten 018**, because 018 did not sign the
referee's boolean. It signed a direction at 0.532 against 0.063 under a worst-case
bound: `(0.532 - 0.063) x 79 = 37.05` net deletions, needing the 29 unscored items to
supply more than `37.05 / 29 = 1.28` ungrounded deletions each against a density of
0.228, which is 5.6x enrichment plus perfect discrimination plus zero collateral plus
truncation running against its own physics. The zero-margin criticism bites only near
the boundary and 018 is a factor of eight from it. What is worth recording is the
latent defect: had the result been marginal, 014's frozen L2 could have signed a coin
flip in either direction.

### 4. L3 collapses algebraically, and hides a value choice

With Δ the paired drop against `sp`, per item:

```
(Ung_sp - Ung_dp) - (Ung_sp - Ung_dv)  >  (Gr_sp - Gr_dp) - (Gr_sp - Gr_dv)
                   Ung_dv - Ung_dp     >    Gr_dv - Gr_dp
```

The cancellation is exact and per-item, so `sp` contributes zero mean *and* zero
variance. L3 is a plain `dp` against `dv` test in a marginal costume, and after 018
that comparator is a signed wrecking ball.

Both L2a and L3 also trade a deleted-ungrounded field against a deleted-grounded field
at **exactly 1:1**. That is not a *tunable* constant, so 014's r14 principle is not
violated, but it is a utility choice wearing the phrase "constant-free", and this
programme has made the same correction once already (P6: "2 x SEM is alpha = 0.05 in a
noise-shaped costume; the real distinction is declared-before-data versus
tuned-after"). For a provenance-first commons 1:1 is the conservative direction, since
a hallucination-averse utility would make the bar *easier* to clear. Declare it, do
not hide it.

### 5. A different model is not a different mind

Draft 1's headline justification was that it crosses an architectural boundary nothing
else has crossed: "MINDfulness gates inwards; Influence gates outwards", described as
"the inter-mind verification line the architecture has never tested".

It does not cross it. **A different model is not a different mind.**

Model B has no DID, no Soul, no charter, no lessons, no inbox and no standing in the
society. It is a second *engine*, called by the same mind, inside the same turn, in
the same process, on the same node. Nothing is published, nothing is routed, no peer
is consulted. Measured against the system's own definition of an agent (a registered
entity with a keypair, a Soul and a mesh identity), swapping the verify seat is an
**intra-agent** change. Draft 1 makes a claim about *models* and dresses it as a claim
about *agents*.

The same reading strengthens draft 1's other classification. It says committees "stay
inside one mind's context", which is right: `committee.erl` drones are **prompt
personas**, not peers. `lenses/0` is five system messages; the committee is one
`gen_server` owned by one convener, ephemeral, dissolving at adjournment. A committee
*publishes* outward (drone lines to its mesh topic, the scribe's report to the agora)
but *consults* nobody. Its output is inter-agent; its deliberation is not.

**The gate's correction:** a committee is nonetheless **not same-engine**. Drones call
`spartan_mind_llm:reason_messages/1`, and that module shuffles the provider schedule
per call (`spartan_mind_llm.erl:257`) in explicit pursuit of "cognitive diversity
(different engines, different families of voice)" (`:6`). So a committee is
**multi-engine by accident**, uncontrolled and unpinned. Two consequences: V1 is the
*controlled* version of something the committee already does stochastically, which
weakens its novelty; and any future committee measurement would confound persona with
engine hopelessly.

The rungs of verification in this system, corrected:

| Rung | Mechanism | Status |
|---|---|---|
| Intra-agent, same engine, same context | MINDfulness (`mindfulness.erl`) | **signed dead on attributed extraction** (018) |
| Intra-agent, N personas, **engine uncontrolled** | committee (`convene_committee/`) | built, never measured, confounded by construction |
| Intra-agent, **second engine, pinned** | what V1 actually tests | this note |
| **Inter-agent, a peer mind on the mesh** | nothing | unbuilt, untested |

The first three are engineering knobs any single-process agent could have. Only the
fourth needs a mesh, DIDs and Souls. It is also unbuilt: `route_message` is
fire-and-forget into an inbox, the agora is a broadcast, and `federation_ask` carries
inbound *visitor* questions into the agora, not mind asking mind. A real inter-agent
gate needs that primitive, plus an answer to what a sovereign entity owes a peer that
asks it to check something, which is a governance question and not only a wiring one.

**One over-claim of mine, corrected at the gate.** I wrote that the peer rung's
decorrelation source is "biography, not pretraining lineage". That is too strong. A
peer mind running the same qwen engine shares the drafter's pretraining blind spots
entirely; a Soul and a charter change the prompt, not the model's error distribution on
mechanical substring grounding. For this task class engine identity plausibly
dominates biography, so the fourth rung does not automatically escape the failure
either. That argues *for* running the cheap ladder first rather than romanticising the
frontier.

Finally, this is why "Influence" is the wrong word for any of the four rungs. If the
system has an Influence faculty at all, its honest referent is intra-agent and is none
of the above: **how far this mind lets another's view move its own**, which is
deference and susceptibility, a modulator in the sense `DESIGN_MIND_FACULTIES.md`
reserves for affect. The fleet has shown it once, in the entity that received an
operator's first-contact message and consciously deferred it with an explicit
sovereignty audit. That is a real faculty and possibly a measurable one. It is not a
second opinion from a second engine, and calling both "Influence" is the folk-label
collapse the design doc exists to forbid.

## Everything else draft 1 got wrong, briefly

- **The corpus is spent.** Draft 1 specified "no new corpus, M1's frozen snapshot and
  calibration slice, unchanged". 016: the 143-item corpus is exhausted, 35 calibration
  plus 108 confirmatory, scored once, and re-scoring it after seeing the feed is the
  shopping pattern. A corpus experiment needs a fresh harvest under 017's frozen
  harvest-window rule. Affordability is not the binding constraint: the hygiene rule is
  portable and the harvest is nearly free. `PROVENANCE.md` already records Euractiv
  returning 403 at the July harvest, and 017's void band covers the drift that
  produces.
- **It forbade repairing an instrument it needs repaired.** Draft 1 says "do not
  reinvent the instrument". 018 parks 017's fix 1 and fix 2 "on the shelf for any
  future experiment that needs a *measured* L2 rather than a bounded direction". This
  is that experiment, at the ladder already, and both fixes are prerequisites. The need
  is stronger here: truncation concentrates in whichever arm writes the longest output,
  so with more than two arms of differing output length an uncorrected truncation
  biases arms *differentially*, which is exactly what made M1 unsignable.
- **No sizing, and no named test.** 003 established pilot-then-power; 017 Finding A
  showed sizing to `E[t] = 2` is 50% power. Worse, draft 1 declares no statistical test
  at all: paired counts here are small discrete integers, so the leg wants an **exact
  sign test** on per-item paired differences at a declared alpha, not a normal SEM
  ratio, which is P6's correction applied here. With four-plus arms and several legs,
  per-test against family-wise alpha must also be declared.
- **It inherited L1 verbatim without 017's boundary statement.** L1 is un-makeable-fair
  at its own 50% threshold for any n. If carried, it is a secondary readout carrying
  that limitation, never a deliverable.
- **The capability-mismatch void is asymmetric.** It voids when B dominates A but not
  when A dominates B, so "the reviewer was simply worse" is an unlicensed third
  mechanism. The band must be symmetric.
- **"Different provider family" is a proxy for a directly measurable precondition.**
  The thesis needs *decorrelated errors*; lab identity is a leaky proxy for it. `sp`
  and `sp_B` give the overlap between A's ungrounded fields and B's, for free, and the
  checker is mechanical so it sees every grounding error regardless of what either
  model can see. Report it always and void on the measured overlap. This is conditional
  on fix 2's per-field retention, which is a further reason fix 2 is not optional.
- **A pass could be undeployable.** The pairing must come from the set the fleet may
  run. M1's only clean endpoint was local `qwen2.5:7b-instruct-q4_K_M` on ollama at
  temperature 0, zero retries across 143 items. So a **second pinned local model of a
  different family** is wanted, which keeps the zero-retry property and satisfies the
  no-Big-Tech-in-the-data-path constraint at once. See the formatter screen above: the
  obvious candidate has already failed it.
- **The name**, per defect 5. The function is a second-engine verification gate on a
  drafted output, inside one mind: `HECATE_MIND_CROSS_ENGINE_VERIFY`.

## What survives from draft 1, and is worth keeping

- **The marginal construct.** "Excess garbage caught beyond the incumbent gate against
  excess good material lost" is a real and previously unasked question in this corpus.
  It is misapplied against `dv` after 018, but it will be needed the moment there is a
  gate worth comparing against.
- **The engineered-to-rescue guard.** "Do not remove the failure mode you are testing;
  measure it" is a good methodological principle, correctly reasoned. It is moot in
  this rig only because the reduction was already there.
- **The precondition void.** Voiding when the thesis's own precondition is unmet,
  rather than reporting a null, is the right instinct. It needs to fire on a
  measurement instead of a proxy.

## The shape of V1, if and only if the ladder licenses it

Not frozen. Runs only if D0 shows attrition small, D1 shows the remove-instruction is
not the whole story, and D2 shows discrimination the self did not.

- **Fresh corpus** under 017's frozen harvest-window rule.
- **Arms, paired per item:** `sp` (single pass, model A); `dv` (self-verify, model A,
  **reported as the known failure, not a comparator**); `xv` (cross-engine verify,
  model B, formatter-qualified, identical `verify_system` prompt and message shape);
  `sp_B` (single pass, model B, for B's own extraction quality and the error overlap
  that tests the decorrelation precondition).
- **No `xv_full`** unless the production-context question is separately funded.
- **Primary criterion:** `xv` against `sp`, discrimination, exact sign test on paired
  per-item differences at a declared alpha, family-wise handling declared, the same
  noise treatment on every leg and no zero-margin conjunct anywhere.
- **Secondary, reported not adjudicated:** `xv` against `dv` and the token ledger, with
  the rig-economy caveat from defect 1.
- **Sizing** off D2's effect estimate, 80% power, upper bound of the variance estimate.
- **Both signed sentences pre-written**, and **the pass sentence must name the pipeline
  that turns the gate on.**
- **Explicitly out of scope:** the inter-agent rung. Routing a draft to a peer mind
  with its own DID, Soul and charter is a different experiment on an unbuilt primitive,
  and V1 must not be reported as evidence about it.

## The deployment question, answered rather than deferred

The gate refused to let this stay hypothetical, and the answer is uncomfortable. **No
production slice currently runs attributed extraction behind a verify gate.**
MINDfulness gates reasoning turns; M1's task was a checkable proxy, chosen for the
checker, not because anything ships it. So on a V1 pass the operational change is a
*future* gate on an ingestion pipeline (the news sensor, sentinel enrichment), plus a
second resident local model at roughly 4 to 5 GB per node and 2x latency on gated
turns. On a fail, nothing changes.

**If no consuming pipeline can be named, the pass sentence is not writeable**, and that
discovery belongs at this gate rather than after a corpus is spent. The honest funding
case for the ladder is not the gate it might ship; it is mechanism knowledge that
scopes the whole verification roadmap, including the peer rung.

## Odds (Fable r15)

- The ladder kills V1 before a corpus is spent: **~65%.** D0 large, ~40 to 50% on the
  anti-discrimination arithmetic; D1 resolves it prompt-side, a further ~15 to 20%; D2
  destroys or is inert, the remainder. Each of those deaths is decision-grade and costs
  an afternoon of local CPU.
- If V1 runs, it dies at its own bar or blocks on the parse gap: **~60%.**
- End to end, this programme produces a deployed cross-engine gate: **~10 to 15%.**

Worth the compute? The ladder unconditionally: it is nearly free, it re-attributes an
already-signed result, and its answer scopes every rung above it including the
peer-mind frontier. The corpus run only on the ladder's licence, which is 018's
meta-result applied forward.

## Next

Build 017 fix 1 and fix 2. Run D0. Nothing else until D0 reports.
