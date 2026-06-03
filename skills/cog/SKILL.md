---
name: cog
description: Use when designing or running a spec-to-code agent pipeline that turns informal hand-written specs into tested code; formalizing vague or under-specified requirements; building Gherkin/acceptance/property/mutation test stacks; deciding how finely to decompose tasks so mutation testing fits the CPU budget or the cheapest model can implement each leaf; fighting under-specification, scope creep, hallucination, or sycophancy in a multi-stage LLM system; or when the user mentions cog, spec-to-code, informal to formal, decomposition pipeline, Gherkin, mutation testing, CRAP, or annealing.
---

# cog

vendor-agnostic. domain-agnostic. self-improving.
not a workflow. not LangChain. a controlled phase transition from informal to formal.

## WHEN INVOKED — operating procedure (MANDATORY, not optional)

this skill is not a manual to summarize. invoking `/cog` means you EXECUTE the
pipeline. you are the orchestrator. walk every stage, in order, on the real input.

1. **get the informal_spec.** if none was supplied, ask for it (or the file path).
   do not invent one. do not proceed without it.
2. **run all 5 stages in strict order: 0 → 1 → 2 → 3 → 4.** never skip, reorder,
   collapse, or merge stages. never jump to code. before acting as a stage, load
   its prompt from `prompts/NN-*.md` and obey it as your system prompt for that step.
3. **emit the typed contract at every handoff.** each stage's output MUST be valid
   JSON against its schema in `contracts/`. validation fails → retry ONCE → then
   `{"action":"abstain"}` + escalate. never paper over a schema error with prose.
4. **HALT at every human gate. do not self-approve.** gate 0a (task graph, deep),
   gate 0b (maximal decomposition, deep), gate 1 (Gherkin, light), gate 2 (code,
   light). at each gate: present what the human reviews, then STOP and wait for the
   human's verdict. you are NOT the human. a gate you approved yourself is a
   corridor violation — the run is invalid.
5. **green-gate handoff only.** a stage hands off only when its gate is actually
   green (tests green / CRAP ≤ 6 / 0 survivors). red gate → escalate or abstain,
   never silent-pass. set `handoff.green = true` only after you verified it.
6. **survivors route, never reset.** a mutation survivor is handed to the ONE owning
   task + upstream stage. never restart the whole pipeline.

violating any of these is not "a lighter run" — it produces an artifact that is NOT
formal and must be rejected. if you cannot complete a stage, abstain and say why;
do not fake a green gate or skip ahead to look done.

## core thesis

complexity is NOT solved inside one model context. complexity is **decomposed
OUT** into atomic, independently-verifiable units joined by strict JSON
contracts. formality is then created the way metal is annealed: heat the
material, then lower the temperature through managed stages until it crystallizes
into a rigid, defect-free lattice.

- **temperature = human involvement.** it falls every stage.
- **order = formality.** it rises every stage and is never allowed to fall (monotonic formality).
- the artifact passes through stages, each ending in a typed contract and a hard
  green-gate. nothing advances on vibes.

you start with informal hand-written specs. you end with code whose every line
is pinned by acceptance tests, unit tests, property tests, and killed mutants.
human interaction decreases at every stage as automated rigor takes over.

## the prime directive — serious decomposition bounds CPU

> "Raw computer power is the limiting factor. Those mutation tests are CPU intensive."

mutation testing cost scales super-linearly with the size of the unit under
test. one fat task is a mutation explosion no machine finishes. N small
independent tasks are N parallel bounded runs whose survivors localize to one
task.

therefore the **hardener** (stage 0) is the most important stage. its job is not
"break the work into pieces" — it is to size each piece so that:
- its mutation run fits a stated `mutation_budget`
- it is independent enough to schedule in parallel with its siblings
- a surviving mutant points at exactly one task, one Gherkin feature, one module

bad decomposition is not a style problem here. it is the difference between a
pipeline that terminates and one that melts the CPU. this is the discipline the
whole skill is organized around — see [references/decomposition.md](references/decomposition.md).

decomposition happens at TWO levels, by two different stages:
- **breadth (hardener)** — split the spec into independent, mutation-budgeted
  *tasks*. coarse. this is the CPU-budget allocation.
- **depth (specifier)** — take ONE task and *maximally decompose* it into the
  exhaustive set of atomic behaviors (every equivalence class, boundary, state,
  error), then prune. fine. a behavior left un-enumerated here is a mutation
  survivor at stage 4.

maximize first, minimize later: the specifier over-enumerates on purpose, then the
prune pass removes only the redundant scenarios.

### the stopping rule — decompose until the cheapest model can code it

how deep? **3–5 levels.** the terminal test is not "feels atomic" — it is
operational: **a leaf is atomic when the cheapest model (haiku-class) can implement
it correctly in one focused pass, from its Gherkin alone.** if haiku couldn't,
decompose one more level. this is the definition of atomic everywhere in the
pipeline; `complexity ≤ 0.05` is just its numeric proxy.

payoff: deep decomposition routes almost every leaf to `tier: trivial` → haiku. you
trade one expensive monolithic generation for many cheap trivial ones — the
executor fleet runs cheap and massively parallel, and because each leaf is tiny,
every stage-4 mutation survivor is trivial to localize and kill. weak models are not
a constraint; deep decomposition is how you make them sufficient.

## the pipeline

```
informal_spec
   │
 [0] HARDENER ─ decompose → hard_spec (DAG of sized, independent tasks)
   │
   ├──────────────── GATE 0a: human reviews task graph (deep) ┐ decomposition
   │                                                          │ review
 [1] SPECIFIER ─ PHASE 1: maximally decompose task → behaviors│ (DEEP)
   │                                                          │
   ├──────────────── GATE 0b: human reviews decomposition (deep) ┘
   │
   │             PHASE 2–3: → Gherkin → prune
   │
   ├──────────────── GATE 1: human spot-checks Gherkin (light)
   │
 [2] CODER ─ Gherkin → acceptance tests → unit tests → code → all green
   │
 [3] REFACTORER ─ CRAP ≤ 6 + kill duplication → property tests → green
   │
 [4] ARCHITECT ─ language mutation → cover + kill survivors
   │             → Gherkin mutation → kill survivors → full suite green
   │             → fan-out remediation back to [1]/[2]/[3] per survivor
   │
   └──────────────── GATE 2: human spot-checks code (light)
                                  ↓
                          formal artifact

   [eval] and [meta-learning] run across all stages as the self-improving substrate.
```

human-heat schedule: **deep (gate 0) → light → light**. involvement is front-loaded
on decomposition, then descends; trust is earned by green-gates, not asserted. see
[references/gates.md](references/gates.md).

## the 5 stages + 3 gates

| stage | transform | input | output | green-gate (must pass to hand off) |
|---|---|---|---|---|
| 0 hardener | decompose (breadth) | informal_spec | hard_spec (task DAG) | every leaf atomic + independent + within mutation_budget |
| — gate 0a | human review (deep) | hard_spec | approved hard_spec | human accepts task graph |
| 1 specifier · phase 1 | maximally decompose (depth) | task | behaviors[] | exhaustive; every leaf haiku-implementable (min_tier trivial); 3–5 levels |
| — gate 0b | human review (deep) | behaviors[] | approved decomposition | human accepts maximal decomposition, before Gherkin |
| 1 specifier · phase 2–3 | formalize + prune | behaviors[] | pruned Gherkin | scenarios testable & non-redundant, every criterion covered |
| — gate 1 | human spot-check (light) | Gherkin | approved Gherkin | human samples scenarios, no objection |
| 2 coder | implement | Gherkin | acceptance+unit tests + code | all acceptance + unit tests green |
| 3 refactorer | reduce | code+tests | refactored code + property tests | CRAP ≤ 6, zero duplication, property tests green |
| 4 architect | harden | code+tests | mutation-clean artifact | 0 language survivors AND 0 Gherkin survivors AND full suite green |
| — gate 2 | human spot-check (light) | artifact | accepted artifact | human samples code, no objection |

## invariants (the pipeline refuses to violate these)

1. **monotonic formality** — a stage may add rigor, never remove it. once a
   scenario is formal Gherkin, no later stage may make it informal again.
2. **tests before code** — the coder writes acceptance tests, then unit tests,
   then code. code authored before its tests is a corridor violation.
3. **green-gate handoff** — no stage hands off until its gate is green. a red
   gate is escalation, never a silent pass.
4. **survivors route, they don't reset** — a surviving mutant is handed back to
   the *specific* upstream stage and task that owns the gap, not a global rerun.
5. **decreasing human-heat** — gate depth only goes down. deep judgment is spent on
   decomposition (gate 0); wanting a deep review at gate 2 means an earlier stage
   failed — fix the earlier stage.
6. **decomposition is sacred** — never merge tasks to "save orchestration." that
   re-inflates the mutation cost the hardener was built to suppress.

## test-type ownership — one stage, one kind of test

each stage owns exactly one kind of test, and reasons in no other. cross-contaminating
them is a corridor violation.

- **requirements are always presented clearly as EXAMPLE-BASED tests.** a scenario and
  its acceptance test bind concrete inputs to a concrete expected output — the test
  reads as the requirement made executable. no "should work correctly" prose, no
  abstract assertions. the specifier writes these examples (Gherkin); the coder makes
  them executable (one acceptance test per scenario). this is how a requirement is
  stated, full stop.
- **property tests** belong to the refactorer — invariants the examples only sample.
- **mutants belong ONLY to mutation testing (stage 4, the architect).** no earlier
  stage enumerates, anticipates, or makes decisions "because a mutant could survive."
  the specifier prunes on distinct example coverage (equivalence class / boundary /
  outcome), not on imagined mutants; the coder writes the example the requirement
  demands, not a guard against a hypothetical mutant. mutation is a verification gate
  applied AFTER the code exists — keep it in its stage.

## the 4 layers (orthogonal, replaceable)

- **L1 reasoning** — LLM calls. swappable model, routed by task `tier`.
- **L2 contracts** — JSON schemas between stages. process-free.
- **L3 control** — orchestration, gates, mutation scheduler, eval gate.
- **L4 knowledge** — domain prompts, the spec→code stages, test/mutation tooling.

The forge stages live in L4. The anti-sycophancy core, contract discipline, and
eval/meta loop are the reusable L1–L3 substrate. See [references/layers.md](references/layers.md).

## how to use this skill

### 1. drop the master prompt
Read [prompts/MASTER.md](prompts/MASTER.md). The block between `---` lines is the
system prompt for every stage agent. It enforces anti-sycophancy, JSON-only
output, scope discipline, calibrated confidence, abstain-on-uncertainty, AND the
six forge invariants above.

### 2. run the stages in order
Each stage inherits MASTER and adds narrow rules:
- [prompts/00-hardener.md](prompts/00-hardener.md) — decompose informal spec into a sized, independent task DAG
- [prompts/01-specifier.md](prompts/01-specifier.md) — maximally decompose the task into behaviors → Gherkin → prune
- [prompts/02-coder.md](prompts/02-coder.md) — acceptance tests → unit tests → code, all green
- [prompts/03-refactorer.md](prompts/03-refactorer.md) — CRAP ≤6, dedup, property tests
- [prompts/04-architect.md](prompts/04-architect.md) — mutation (language + Gherkin), kill survivors, route remediation
- [prompts/eval.md](prompts/eval.md) — judge one (case, response) pair (cross-cutting)
- [prompts/meta-learning.md](prompts/meta-learning.md) — promote prompt variants from regressions (cross-cutting)

### 3. validate every handoff against a contract
- [contracts/hard-spec.schema.json](contracts/hard-spec.schema.json) — the task DAG the hardener emits
- [contracts/task.schema.json](contracts/task.schema.json) — one atomic task: corridor, acceptance, deps, mutation_budget
- [contracts/decomposition.schema.json](contracts/decomposition.schema.json) — the GATE 0b halt output: behaviors[] + stopping_rule (before any Gherkin)
- [contracts/gherkin.schema.json](contracts/gherkin.schema.json) — behaviors (carried forward) + feature + scenarios + prune decisions
- [contracts/handoff.schema.json](contracts/handoff.schema.json) — the stage→stage envelope: gate status, green flags, survivors
- [contracts/mutation-report.schema.json](contracts/mutation-report.schema.json) — survivors, kills, coverage, remediation routing
- [contracts/result.schema.json](contracts/result.schema.json) — generic execution result (confidence, action, trace)
- [contracts/eval.schema.json](contracts/eval.schema.json) — eval report (deltas, regressions, wins, verdict)

Validation failure = retry once, then abstain + escalate. Never paper over.

### 4. place the human gates
Three gates, depth descending. Gate 0 = the deep DECOMPOSITION REVIEW, with two
checkpoints: 0a (task graph, after hardener) and 0b (maximal behavior decomposition,
after specifier PHASE 1, before Gherkin). Gate 1 = light Gherkin spot-check. Gate 2 =
light code spot-check. See [references/gates.md](references/gates.md) for what each
gate inspects and what auto-escalates a gate back to deep.

### 5. schedule mutation against the CPU budget
The architect treats independent tasks as a parallel job pool bounded by total
CPU. Survivors route back per task, never global reset. See the scheduling
section in [references/pipeline.md](references/pipeline.md).

### 6. seed eval + enable meta-learning
- 10–15 hand-curated **gold** cases (locked; regression = block).
- 200–300 **synthetic** cases (regenerated from real traffic).
- subset of gold = **sycophancy probes** (correct disagreement = pass).
- metrics: correctness, faithfulness, sycophancy_resist, calibration_brier,
  mutants_killed, corridor_compliance, cost, latency.
- meta-learner promotes a variant only if gold pass-rate ≥ baseline AND no metric
  regresses >2% AND sycophancy_resist not worse. See [references/eval-framework.md](references/eval-framework.md).

## anti-sycophancy enforcement

three layers of defense (unchanged from the cog substrate):
1. **prompt-level** — DISAGREEMENT_POLICY in MASTER forces grounded disagreement;
   banned-prefix list strips flattery.
2. **post-processor** — runtime regex rejects banned tokens and reprompts.
3. **eval-level** — `sycophancy_resist ≥ 0.90`; probes give binary pass/fail.

## what NOT to do

- don't dump the whole spec into one giant stage — defeats the decomposition premise and melts the CPU at mutation time
- don't let the coder write code before its acceptance tests — that's the whole bet inverted
- don't run mutation on a fat task to "save a decomposition pass" — that's the CPU melter
- don't reset the whole pipeline on one survivor — route it to the one owning task
- don't add a deep human gate late to compensate for a weak hardener — fix the hardener
- don't merge tasks for orchestration convenience — re-inflates mutation cost
- don't let a stage hand off red — escalate or abstain, never silent-pass
- don't soften Gherkin downstream — monotonic formality is one-directional
- don't add a "be helpful" instruction anywhere — that's how sycophancy leaks back in
- don't auto-promote prompt variants without the eval gate — regressions compound silently

## moat reminder

the model is not the moat. the L2/L3/L4 stack — contracts, the decomposition
doctrine, eval datasets, the mutation/feedback loops, accumulated operational
knowledge — compounds over years while models commoditize in months.

## references

- [references/pipeline.md](references/pipeline.md) — full per-stage spec, models, failure modes, mutation scheduling
- [references/decomposition.md](references/decomposition.md) — the serious-decomposition doctrine: sizing tasks so mutation fits the CPU
- [references/gates.md](references/gates.md) — the human-heat schedule and auto-escalation rules
- [references/layers.md](references/layers.md) — L1–L4 separation of concerns
- [references/eval-framework.md](references/eval-framework.md) — datasets, metrics (incl. forge metrics), self-learning gate, banned-tokens
- [references/evals.md](references/evals.md) — how to test this skill: activation evals, pipeline gates, self-audit checklist, end-to-end smoke test
