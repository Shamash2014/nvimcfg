# stages

## [0] decomposer

**in**: `{ task: string, context?: object, max_depth: 5 }`
**out**: `task.json` (tree of subtasks)

rules:
- split into 5-10 children
- estimate complexity per child (0..1)
- recurse on children where complexity > 0.05
- leaf = atomic, single-responsibility subtask
- pareto check: 1-2 hard / 7-9 trivial per level. if all hard → split harder. if all trivial → merge.

model: mid-tier (sonnet-class). cheap enough, smart enough for tree shape.

failure mode: if depth > max_depth and complexity still > 0.05 → flag for human triage. do not force.

## [1] md→json converter

**in**: `{ system_prompt_md: string, user_prompt_md: string, schema_ref: string }`
**out**: `subtask.json` matching `schema_ref`

rules:
- cheap model only (haiku-class). this is parsing, not reasoning.
- output MUST validate against referenced JSON schema
- on validation fail → retry once with error in context. fail twice → escalate.
- strip narrative. keep only: goal, inputs, constraints, expected_output_shape.

why cheap model: this stage is high-volume and structural. paying smart-model price here is waste.

## [2] focused executor

**in**: `subtask.json` (one leaf)
**out**: `result.json`

each subtask prompt MUST contain:
- `goal` — one sentence
- `inputs` — typed
- `solution_corridor` — what's in scope, what's out
- `quality_criteria` — checklist
- `eval_metrics` — how output will be scored
- `output_schema` — JSON shape

model: routed by subtask `tier` field. trivial → haiku. complex → opus. unknown → start cheap, escalate on low confidence.

confidence: every result includes `{ confidence: 0..1, uncertainty_sources: string[] }`. low confidence → reroute or human review.

## [3] aggregator

**in**: `result.json[]` + parent `task.json`
**out**: `output.json`

rules:
- validates child results satisfy parent contract
- merges typed outputs (no string concat magic)
- on contract violation → re-decompose offending branch, do not paper over
- emits trace: which subtask → which executor → which prompt version → which model

## [4] eval loop

**in**: `output.json` + gold + synthetic
**out**: `eval.json` (metrics, regressions, deltas)

runs:
- gold cases (10-15 manual, high-signal)
- synthetic cases (200-300, generated from real traffic patterns)
- per-metric scoring (correctness, faithfulness, latency, cost, calibration)
- diff vs prior prompt versions

emit: `{ pass_rate, regressions[], wins[], cost_delta, latency_delta }`

## [5] meta self-learning

**in**: `eval.json` stream
**out**: `prompt_version` bump + new variants

rules:
- if new variant beats baseline on gold AND no regression on synthetic → promote
- if variant regresses gold → demote, never auto-promote
- generate candidate variants by: perturbing corridor, tightening criteria, swapping examples
- A/B in shadow before promotion
- keep last N versions for rollback

background loop: runs continuously. user traffic = additional synthetic case generator.
