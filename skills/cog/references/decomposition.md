# the serious-decomposition doctrine

decomposition is not the first step of this pipeline. it is the step the pipeline
exists to get right. every later stage's correctness and, crucially, its CPU cost
are bounded by how the work is sized.

## two levels of decomposition (two stages own them)

decomposition is not a single act. it happens twice, at two granularities, owned by
two stages — and the second one is where the *maximal* decomposition lives:

- **breadth — the hardener — splits the spec into TASKS.** coarse units that are
  independent and mutation-budgeted. one task ≈ one observable behavior / one
  module. this is the CPU-budget allocation (see below). the hardener does NOT
  enumerate every scenario inside a task — that would be the wrong altitude.
- **depth — the specifier — MAXIMALLY DECOMPOSES one task into BEHAVIORS.** the
  exhaustive set of atomic, independently-observable behaviors: every input
  equivalence class, boundary, state transition, and error path. this is the
  finest grain, and it is the specifier's job, not the hardener's.

the rule that ties them: **maximize first, minimize later.** the specifier
over-enumerates on purpose (PHASE 1), formalizes each behavior as Gherkin
(PHASE 2), then prunes only the redundant scenarios (PHASE 3). a behavior the
specifier fails to enumerate is not caught by anyone downstream — it surfaces as a
surviving mutant at stage 4, which then routes back to the specifier anyway. do the
enumeration up front.

## the stopping rule — decompose until the cheapest model can code it

how deep is deep enough? **3–5 levels.** but the real terminal test is not a level
count — it is operational:

> a leaf is atomic when the **cheapest model (haiku-class)** can implement its code
> correctly in ONE focused pass, from its Gherkin alone.

if haiku couldn't, decompose one more level. `complexity ≤ 0.05` is just the numeric
proxy for this; `min_tier: trivial` on a behavior is its concrete assertion. this is
the definition of "atomic" used at both levels — breadth and depth.

### why "haiku can code it" is the right target

- **cost** — deep decomposition routes the overwhelming majority of leaves to
  `tier: trivial` → haiku. you trade one expensive monolithic generation for many
  cheap trivial ones. the executor fleet runs at haiku prices.
- **parallelism** — trivial independent leaves saturate a wide worker pool; wall-clock
  collapses toward the slowest single leaf.
- **mutation localization** — a tiny leaf has a tiny mutant population and a tiny
  suite. a survivor points at a few lines, not a module. killing it is trivial too.
- **reliability** — a weak model on a trivial, fully-specified leaf is more reliable
  than a strong model on an under-specified fat task. depth converts model weakness
  into a non-issue. weak models are not a constraint; decomposition is the lever.

the failure this prevents: stopping decomposition at "a smart model could do this."
that ships a fat leaf to the coder, inflates the stage-4 mutant population, and burns
opus tokens where haiku would have sufficed had the work been split two more levels.

## the decomposition review (gate 0)

because decomposition decides everything downstream, it is the one place the human
spends DEEP attention — gate 0, with two checkpoints: 0a reviews the task graph
(breadth) after the hardener; 0b reviews the maximal behavior decomposition (depth)
after the specifier's PHASE 1, BEFORE any Gherkin or pruning. reviewing the
decomposition before pruning is deliberate: pruning after an unreviewed decomposition
would hide gaps the human never saw. see gates.md.

## why decomposition is the CPU lever

mutation testing generates a population of mutants and runs the test suite against
each. cost ≈ (mutant count) × (suite runtime). both factors grow with the size of
the unit under test:

- a fat task has more lines → more mutants, and a slower, broader suite → each
  mutant costs more. the product grows faster than linearly. on real code this is
  the difference between minutes and "never finishes."
- N small independent tasks have small mutant populations and fast local suites,
  AND they run in parallel. total wall-clock ≈ the slowest single task, not the sum.

so the hardener is not chasing "clean architecture." it is allocating the CPU
budget. `mutation_budget` per task is the unit of that allocation.

## what a correctly-sized task looks like

1. **atomic** — one observable behavior, one acceptance-criteria set, one module's
   worth of code, testable in isolation.
2. **independent** — shares no mutable state with siblings; its mutation run can
   execute concurrently with theirs. DAG dependencies are fine (and explicit);
   shared mutable state is not.
3. **budget-fitting** — estimated mutant count ≤ `mutation_budget.max`. if it
   doesn't fit, split until it does.
4. **non-overlapping corridor** — no sibling can kill the same mutant. this is what
   makes a survivor at stage 4 point at exactly one task.

## the localization payoff

corridor non-overlap + independence buys the single most valuable property of the
whole pipeline: **a surviving mutant names one task.** that turns remediation from
"something somewhere is under-tested" into "task T-014's boundary check is weak,
route it to the coder." no global reset, no hunting. the architect's
`remediation_routes` are only meaningful because the hardener kept corridors disjoint.

## sizing heuristic (pareto, recursive)

at each level expect 1–2 hard children and 7–9 trivial ones.
- all children uniformly hard → split is too coarse → split again.
- all children uniformly trivial → over-split → merge (ONLY here, before handoff —
  never merge downstream).
recurse on any child with `complexity > 0.05`, depth cap 5. if a node won't go
atomic by depth 5, flag it for human triage; do not force a fake leaf.

## the failure you are preventing

the tempting move is "one task per feature, we'll decompose inside the coder."
that pushes a fat unit into stage 4, where its mutation run explodes and the whole
pipeline stalls on one task while the CPUs that could be running siblings sit idle.
the merge-for-convenience instinct is exactly what invariant 6 forbids. small,
independent, budget-fitting tasks are the product of this stage — not a cost to
minimize.

## checklist (hardener must pass all before gate 0a)

- [ ] every leaf atomic
- [ ] every leaf independent (no shared mutable state with siblings)
- [ ] every leaf estimated_mutants ≤ mutation_budget.max
- [ ] sibling corridors disjoint
- [ ] dependency edges acyclic
- [ ] acceptance_criteria observable + falsifiable
- [ ] sum of per-task budgets ≤ available CPU envelope
