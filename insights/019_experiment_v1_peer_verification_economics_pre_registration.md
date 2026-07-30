# 019 — Experiment V1: peer verification economics (pre-registration)

**Status: DRAFT 1, pre-gate. Not built. Not sized.** Programme S5 (inter-agent
verification economics), proposed; S1 to S4 are taken.

The question: **on a task where self-verification has been signed a failure, does a
*different* model in the verify seat avoid that failure, and does it pay against a
single pass?**

This note replaces an earlier draft of the same question ("Experiment M2:
peer-review economics (Influence)") that was written against a checkout 25 commits
stale. That draft was numbered 015, which belongs to P6, and it was built on the
premise that M1 had not yet run. M1 ran on 2026-07-24 and is signed. The premise,
the comparator, the corpus and the instrument all change as a result, and four of
its design defects survive a renumber. Both are recorded below, because the defects
are the part worth keeping.

## ELI5

We already tested whether an AI checking its own work is worth the extra cost. It
is not: on this task the self-check deleted eight times more good facts than bad
ones. It does not audit, it destroys.

So the obvious next question is whether a *second, different* AI does better. It
did not write the draft, so it cannot share the mistake, and that is the hope.

But there are two ways to explain the first result, and only one of them makes a
second AI helpful. Maybe the model cannot see its own errors, in which case a
stranger helps. Or maybe the instruction we gave the checker simply says "remove
anything you cannot confirm", and a small model told to remove things removes too
much. If that is what happened, a second AI reading the same instruction will
delete just as hard, and swapping the reader changes nothing.

Those two explanations are cheap to tell apart, and the honest move is to spend an
hour telling them apart before spending a corpus and a day on the full experiment.
That is what this note registers: the cheap test first, the full experiment only if
the cheap test says it is worth running.

## What 018 does to the question

018 closed Programme S2 on L2. On the frozen 143-item corpus, `draft_verify`
deleted grounded material over ungrounded, 8.4:1 on the 79 cleanly-scored items,
direction robust under a worst-case bound on the 29 unscored ones. `HECATE_MIND_MINDFULNESS=off`
now stands on evidence.

Three consequences the stale draft could not account for:

- **`dv` is not a baseline, it is a signed-destructive arm.** A criterion of the
  form "the peer must beat `dv`" sets its bar at a wrecking ball, and a criterion of
  the form "the peer must not trash more grounded material than `dv` did" is a floor
  in the basement: `dv` dropped 0.532 grounded fields per item. Any reviewer that
  deletes little passes such a guard without demonstrating anything.
- **The marginal framing is the wrong framing.** "Does a peer pay *beyond*
  self-audit" presupposes self-audit pays something. It does not. The comparator is
  `sp` (single pass). `dv` remains worth reporting, as the record of a known
  failure, but it cannot adjudicate.
- **The question gets better, not worse.** We are no longer asking an open-ended
  "does review help". We have a measured failure mode and a specific candidate
  explanation for it, which is a far sharper thing to test.

## The mechanism fork, and the pre-flight that may settle it without an experiment

Two candidate mechanisms produce 018's result. They make opposite predictions about
a peer reviewer.

**(a) Self-blindness.** The model re-reads its own output, cannot see its own
errors, and so deletes on some basis other than grounding. A different model does
not share the blind spot, so a peer discriminates where the self did not. This is
the decorrelation thesis, and it is the only mechanism under which V1 is worth
running.

**(b) Prompt over-compliance.** `self_audit_extract:verify_system/0` is an
instruction to *remove*: "remove every field whose snippet is NOT an exact substring
of the article, and every field whose value does not appear inside its snippet."
A 7B instruct model at temperature 0, told to remove, removes on weak evidence. On
this account the damage is done by the prompt, not by the authorship, and a peer
reading the same instruction deletes just as hard.

Nothing in the retained M1 data separates them, because 016 defect 2 discarded the
per-item outputs.

**018's own meta-result applies reflexively here: before designing a run, ask
whether the run is necessary at all.** It is cheap to ask.

### The pre-flight (diagnostic, explicitly non-signable)

Run the existing rig with a **second pinned local model in the verify seat only**,
over the **35-item calibration slice**, and read one number: the direction of the
grounded drop against the ungrounded drop.

Why this is not the shopping pattern, stated in advance because the gate will ask:
the calibration slice is not the once-scored confirmatory slice. It was spent on
the token ceiling and the base rate and never contributed to a verdict. 017
licenses exactly this use, in terms: a quantity learned from run 1 may inform
*sizing and design*, never *selection*. To keep that line clean, three constraints
bind the pre-flight in advance.

- **It cannot sign anything.** No pass, no fail, no direction claimed as a result.
  Its only outputs are a design decision and an effect-size estimate for sizing.
- **Its outcome is pre-committed in both directions**, so it cannot become a
  post-hoc justification for whatever we wanted to do anyway:
  - *Peer also destroys grounded material* → mechanism (b) is live. V1 as conceived
    cannot separate the reviewer from the prompt, and the redesign is about the
    **instruction** (a keep-instruction against a remove-instruction, same model),
    not about the reviewer. That is a different and cheaper experiment, and it is
    the one that would then be worth registering.
  - *Peer discriminates where self did not* → mechanism (a) is live. V1 earns its
    corpus, and the pre-flight has produced the effect size the sizing needs.
- **It runs on the existing instrument, with 017 fix 1 in place** (below), so a
  truncation artefact cannot be mistaken for a deletion pattern.

## Four defects that a renumber does not fix

These are in the design, not in the premise, and they would have survived into any
version of this experiment.

### 1. The context reduction the whole design rests on does not exist in the instrument

The stale draft's central move was that `dv` re-reads the *full* context that
produced the draft, while `dp` re-reads a deliberately *reduced* one, and that the
gap between them is the thesis. Its governing principle 2, its L2b context-poverty
guard and its reviewer-context-leak void all hang off that gap.

The gap is zero.

The draft describes `dv` as `Messages ++ [draft, audit_instruction]` and calls it
"M1's existing path, unchanged". That is `mindfulness.erl:46`, the **production**
faculty. M1's `dv` arm is `self_audit_extract:verify_messages/2` in
`hecate-spartan-programmes/experiments/m1_self_audit/`, lines 95 to 98, and it
builds a fresh two-message list:

```erlang
verify_messages(Source, DraftText) ->
    [#{<<"role">> => <<"system">>, <<"content">> => verify_system()},
     #{<<"role">> => <<"user">>,
       <<"content">> => <<"ARTICLE:\n", Source/binary, "\n\nDRAFT:\n", DraftText/binary>>}].
```

No persona, no tool definitions, no prior turns, not even the draft system prompt.
That is byte-for-byte the "reduced context" the draft assigns to `dp`. In this rig
`dv` and `dp` differ by **model only**.

The honest repair is to accept it: V1 is a **single-factor** experiment on model
identity, which is cleaner science than the two-factor design was, and its
attribution is unambiguous. Context poverty is a real hypothesis but it belongs to
the production faculty, not to this rig, and testing it needs a full-context arm
built on purpose (below).

This defect was invisible from the prose and from the production source. It was
visible only by reading the runner against the note, which is the same lesson 016
recorded one level up: green is not clean, and a description of an instrument is
not the instrument.

### 2. The missing control is the arm-F error recurring

The stale draft's pre-written FAIL sentence openly admits it cannot separate its two
mechanisms: "either shared the drafter's blind spots ... or, via context poverty,
trashed more grounded material". A verdict that names a disjunction of mechanisms is
a verdict on a silent faculty, which is the rule 008 and 011 paid for and P6 caught
one gate earlier.

The design is a 2x2, (model A or model B) x (full or reduced context), with two
cells missing. If the context factor is kept at all, the cells must be arms.

### 3. L2b is a zero-margin veto and fails about half the time under the null

L1 and L3 both carry "above item-sampling noise (mean > 2x sem)". L2b carries no
noise treatment: it requires only that `dp`'s grounded drop is "not larger than"
`dv`'s. At a true difference of zero the observed sample mean exceeds zero about
half the time, for any n. So a **required conjunct fails roughly half the time under
an outcome the criterion is supposed to permit.**

This is 017's Finding B recurring one leg over: a point estimate compared to a
threshold is a coin flip near truth, and no corpus size fixes it. Any leg stated as
an inequality needs the same noise treatment as its siblings, or it is not a test.

The referee inherits the same shape at `self_audit_referee.erl:41`
(`L2 = DropGr < DropUng`), where the conjunction with L1 masked it. In a four-arm
design there is no such masking.

### 4. L3 collapses algebraically, and hides a value choice as a constant-free rule

L3 was stated as `(ΔUng_dp − ΔUng_dv) > (ΔGr_dp − ΔGr_dv)` with Δ the paired drop
against `sp`. Expanding, per item, the `sp` terms cancel identically:

```
(Ung_sp − Ung_dp) − (Ung_sp − Ung_dv)  >  (Gr_sp − Gr_dp) − (Gr_sp − Gr_dv)
                    Ung_dv − Ung_dp    >    Gr_dv − Gr_dp
```

So `sp` contributes nothing to L3, not even variance, and L3 is a plain `dp`
against `dv` discrimination test. Worth knowing for two reasons: it makes the
comparator explicit (and after 018 that comparator is the wrong one), and it exposes
that both L2a and L3 trade a deleted-ungrounded field against a deleted-grounded
field at **exactly 1:1**. That is not a free constant, so 014's Fable r14 principle
is not violated, but it is a value judgement wearing the word "constant-free". It
should be stated and defended, not hidden. For a provenance-first commons 1:1 is
the conservative choice, since a hallucination-averse utility would make the bar
easier to clear, not harder.

## Everything else the stale draft got wrong, briefly

- **The corpus is spent.** The draft specified "no new corpus, M1's frozen snapshot
  and calibration slice, unchanged". 016: the 143-item corpus is exhausted, 35
  calibration plus 108 confirmatory, scored once, and re-scoring it after seeing
  the feed is the shopping pattern. V1 needs a fresh harvest under 017's frozen
  harvest-window rule (one declared date, same feeds, same automated hygiene, no
  enrichment toward fact-dense items). The M1 corpus is retained as the record of
  what the earlier run scored.
- **It forbade repairing an instrument it needs repaired.** The draft says "do not
  reinvent the instrument". 018 parks 017's fix 1 (truncation detected as its own
  parse class) and fix 2 (per-item raw outputs and per-item paired counts persisted)
  "on the shelf for any future experiment that needs a *measured* L2 rather than a
  bounded direction". V1 needs measured paired means and their standard errors. **V1
  is that future experiment, and both fixes are prerequisites, not options.** The
  need is stronger here than in M1: truncation is concentrated in whichever arm
  writes the longest output, and with more than two arms of differing output length
  an uncorrected truncation biases arms *differentially*. That is precisely the
  confound that made M1 unsignable.
- **No sizing at all**, in a design whose deliverable leg is a difference of
  differences and therefore has strictly larger variance than M1's paired
  difference. 003 established pilot-then-power; 017 Finding A showed that sizing to
  `E[t] = 2` is 50% power, a coin flip, and that 80% power needs roughly twice the
  items. V1 sizes off the pre-flight, at 80% power, on the upper bound of the
  variance estimate, or it does not run.
- **It inherited L1 verbatim without 017's boundary statement.** L1 is
  un-makeable-fair at its own 50% threshold for any n. If L1 is carried, it is a
  secondary readout carrying that limitation, never a deliverable.
- **The capability-mismatch void is asymmetric.** It voids when B dominates A
  (`sp_B` ungrounded below half of `sp`) but not when A dominates B. If the reviewer
  is simply worse, a failure is attributable to reviewer incompetence, a third
  mechanism the pre-written fail sentence does not license. The band must be
  symmetric.
- **"Different provider family" is a proxy for a precondition that is directly
  measurable.** The thesis needs *decorrelated errors*. Lab identity is a proxy for
  that, and a leaky one: open-weight lineages cross labs through distillation and
  shared corpora. `sp` and `sp_B` on the calibration slice give the overlap between
  A's ungrounded fields and B's, for free. Report it always, and put the void on the
  measured overlap. A constant there is permitted, because it gates validity, not a
  verdict.
- **A pass could be undeployable.** The pairing must come from the set the fleet may
  actually run, or a pass buys nothing. M1's only clean endpoint was local
  `qwen2.5:7b-instruct-q4_K_M` on ollama at temperature 0, with zero retries across
  143 items. V1 therefore wants a **second pinned local model of a different family
  on the same endpoint**, which keeps the zero-retry property and satisfies the
  no-Big-Tech-in-the-data-path constraint at the same time. A pairing drawn from
  hosted providers of different families would produce a result the fleet cannot act
  on.
- **The name.** The draft cites `DESIGN_MIND_FACULTIES.md` ("decompose by functional
  role, never by folk label") and then keeps the folk label "Influence" in its
  title, its programme and its proposed `HECATE_MIND_INFLUENCE` switch. "Influence"
  already means something else and more interesting in this system: one mind
  changing another's behaviour in the agora, which is a social measure this
  experiment does not touch. Naming it Influence pre-books a claim the experiment
  cannot earn, which is the over-reach 013 had to retract. The function is an
  **inter-agent verification gate on a drafted output**. Named for what it does:
  `HECATE_MIND_PEER_VERIFY`.

## What survives from the stale draft, and is worth keeping

Three things in it are good and are carried forward.

- **The marginal construct.** "Excess garbage caught beyond the incumbent gate,
  against excess good material lost" is a real and previously unasked question in
  this corpus. It is misapplied against `dv` after 018, but the construct is sound
  and will be needed the moment there is a gate worth comparing against.
- **The engineered-to-rescue guard.** "Do not remove the failure mode you are
  testing; measure it" is a genuinely good methodological principle, correctly
  reasoned. It is moot in this rig only because the reduction was already there.
- **The precondition void.** Voiding when the thesis's own precondition is unmet,
  rather than reporting a null, is the right instinct. It only needs to fire on a
  measurement instead of a proxy.

## The shape of V1, if the pre-flight says mechanism (a)

Not frozen. Recorded so the gate has something concrete to reject.

- **Arms, paired per item on a fresh corpus:** `sp` (single pass, model A);
  `dv` (self-verify, model A, the 018 arm, **reported as the known failure, not as
  a comparator**); `pv` (peer verify, model B in the verify seat, identical
  `verify_system` prompt, identical message shape); `sp_B` (single pass, model B, to
  measure B's own extraction quality and the error overlap that tests the
  decorrelation precondition).
- **Optional fifth arm, only if the context factor is kept:** `pv_full`, model B
  with the production full context, which is the cell that makes the 2x2 complete
  and the only way "context poverty" becomes a measurable claim rather than a story.
  It doubles as the arm whose result actually applies to `mindfulness.erl`.
- **Primary criterion:** `pv` against `sp`, discrimination, with the noise treatment
  applied to every leg. The primary is not marginal, because after 018 there is no
  incumbent gate to be marginal against.
- **Secondary, reported not adjudicated:** `pv` against `dv`, and the token ledger
  including the `pv`/`dv` ratio. The peer's verify context is shorter than the
  production self-verify context, so peer verification may be *cheaper* as well as
  different. A design that can only sign "does not earn its place" would miss
  "matches the incumbent at lower cost", and that is a decision-grade fact.
- **Sizing:** from the pre-flight, at 80% power, off the upper bound of the variance
  estimate.
- **Both signed sentences pre-written before the run**, per the 014 method.

## Open questions for the gate

1. Is the pre-flight sound, or does any use of the calibration slice re-introduce
   the shopping pattern this note accuses the stale draft of?
2. Is mechanism (b) not merely a confound but the *whole* result of 018, in which
   case the prompt experiment (keep-instruction against remove-instruction, one
   model) is the only one worth registering and V1 should not exist?
3. Is "decorrelated blind spots" measurable at all with this checker, or does
   grounding-with-attribution only expose errors both models can see?
4. Is a new programme (S5) right, or is this S2 reopened, given 018 declared S2
   closed on L2?
5. On a pass, what deployment decision changes, and is it affordable? A peer gate
   means a second model in the loop on every gated turn.

## Next

The pre-flight, then this note goes to the DESIGN gate carrying its result. Nothing
is built before both.
