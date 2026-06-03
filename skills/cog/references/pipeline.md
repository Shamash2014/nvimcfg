# pipeline — full per-stage spec

informal_spec → [0] hardener → 0a → [1] specifier(phase1) → 0b → (phase2-3) → 1
→ [2] coder → [3] refactorer → [4] architect → 2 → formal artifact.
eval + meta-learning run across all stages.

human-heat is front-loaded on decomposition (gate 0 deep), then descends to light
spot-checks (gates 1, 2). formality only rises (monotonic).

## [0] hardener — decompose

**in**: `{ informal_spec: string, context?, cpu_envelope?: number }`
**out**: `hard-spec.json` (DAG of `task.json`)

rules:
- split into 5–10 children, recurse where complexity > 0.05, depth cap 5
- leaf = atomic + independent; sibling corridors disjoint
- every leaf carries a `mutation_budget`; size DOWN until estimated mutants ≤ budget
- pareto per level: 1–2 hard / 7–9 trivial
- merge only here (pre-handoff), never downstream

model: mid-tier (sonnet-class) — tree shape needs judgment, not raw power.
failure mode: not atomic by depth 5 → flag for human triage, do not force.
why it matters most: task size IS the stage-4 CPU allocation. see decomposition.md.

→ **GATE 0a (deep)**: human reviews the task graph (breadth decomposition). part of
the decomposition review; approval licenses the lighter gates downstream.

## [1] specifier — formalize

**in**: one `task.json` leaf
**out**: `gherkin.json` (behaviors + feature + scenarios + coverage_map + prune_log)

three phases — maximize first, minimize later:
- **PHASE 1 maximally decompose**: enumerate the COMPLETE set of atomic behaviors the
  task can exhibit (every equivalence class, boundary, state transition, error path).
  this is the maximal decomposition, and it is the specifier's job — the hardener
  only sized tasks for breadth. STOPPING RULE: go 3–5 levels deep, stop only when each
  leaf is haiku-implementable in one pass (`min_tier: trivial`); else split deeper.
  over-enumerate; a behavior missed here is a stage-4 survivor. record in `behaviors[]`.
  then HALT for gate 0b.

→ **GATE 0b (deep)**: human reviews the maximal behavior decomposition, BEFORE any
Gherkin (so pruning can't hide gaps). part of the decomposition review. approve, or
send back to decompose further. only then does the specifier continue:

- **PHASE 2 formalize**: each behavior → ≥1 scenario; one When per scenario; concrete
  values; stay in corridor (adjacent behavior belongs to a sibling task).
- **PHASE 3 prune**: drop equivalence-class duplicates and untestable scenarios; KEEP
  anything a mutant could uniquely survive against; never prune a criterion to zero
  coverage; log every decision.

model: standard-tier for phase 1–2 reasoning; the coder fleet downstream runs haiku
because the decomposition made every leaf trivial.
failure mode: criterion not observable → ask (bad criterion from hardener, surface it).

→ **GATE 1 (light)**: human spot-checks a sample of pruned Gherkin.

## [2] coder — implement (tests first)

**in**: `gherkin.json`
**out**: `result.json` payload { acceptance_tests, unit_tests, code_modules, test_run, traces }

strict order: acceptance tests (red) → unit tests (red) → minimum code → all green.
rules:
- never write code before its tests are red
- one acceptance test per scenario; unit tests pin branches/boundaries
- minimum implementation; no scope leak; no logging/comments-as-explanation
- a scenario you cannot satisfy → escalate to specifier, never silent-drop

model: routed by task `tier` — trivial→haiku, complex→opus.
green-gate: acceptance + unit both green → handoff to refactorer.

## [3] refactorer — reduce

**in**: green code + tests
**out**: `result.json` payload { refactored_modules, property_tests, metrics, test_run }

rules:
- CRAP ≤ 6 for every function (simplify control flow and/or raise coverage; never by
  deleting assertions)
- zero duplication; extract shared rules to one named unit, within the corridor
- behavior FROZEN — acceptance suite is the oracle; run it after every extraction
- add property tests for invariants (idempotence, round-trip, bounds, ...); must pass
- a false invariant → escalate to specifier; CRAP unreachable without over-splitting →
  escalate to hardener (under-decomposed)

green-gate: acceptance + unit + property green AND crap_max ≤ 6 AND duplication == 0.

## [4] architect — harden (the mutation gate)

**in**: refactored code + full test set
**out**: `mutation-report.json`

two passes:
- **language mutation**: cover uncovered lines first, then kill every surviving
  mutant by strengthening tests. target 0 survivors.
- **gherkin mutation**: mutate the spec (drop a Then, flip a boundary, weaken a
  precondition); a survivor = a scenario the acceptance suite doesn't pin. kill by
  strengthening the bound test, or route to specifier to add the scenario. target 0.
- then run the ENTIRE suite (acceptance + unit + property) → must be green.

green-gate: language_survivors == 0 AND gherkin_survivors == 0 AND suite green.
survivor routing: each unresolved survivor → the ONE owning stage+task (never a
global reset). budget: stay within `mutation_budget`; if the last survivors would
require exceeding it, escalate to hardener for re-decomposition.

→ **GATE 2 (light)**: human spot-checks a sample of code.

## mutation scheduling (the CPU-bound part)

tasks are independent by construction → their mutation runs form a parallel job pool
bounded by total CPU:
- schedule tasks across cores; wall-clock ≈ slowest single task, not the sum
- each run is capped by its `mutation_budget`; a task that would exceed it does not
  blow the pool — it escalates to the hardener instead
- survivors route per task and fan out as independent remediation jobs; the rest of
  the pipeline keeps moving
- this is why the hardener's sizing is the real CPU-budget allocation — see
  decomposition.md

## eval + meta-learning (cross-cutting substrate)

every (stage_input, output, gate_result, prompt_version) tuple feeds the eval store.
the meta-learner generates ≤5 prompt variants per stage per cycle, shadow-tests on
synthetic cases, and promotes only if gold pass-rate ≥ baseline, no metric regresses
> 2%, and sycophancy_resist is not worse. mutants_killed is a first-class metric.
see eval-framework.md and prompts/eval.md, prompts/meta-learning.md.
