# the human-heat schedule

human involvement is a temperature. it is FRONT-LOADED on decomposition — the
load-bearing act — and then descends. there are three human gates; gate 0 is deep
(and has two checkpoints because decomposition happens at two levels), gates 1 and 2
are light. depth only ever decreases, never rises (the decreasing-human-heat invariant).

```
gate 0   DECOMPOSITION REVIEW   DEEP
   0a  after hardener            — review the task graph (breadth decomposition)
   0b  after specifier PHASE 1   — review the maximal behavior decomposition (depth)
gate 1   after specifier         LIGHT — spot-check a sample of pruned Gherkin
gate 2   after architect         LIGHT — spot-check a sample of code
```

decomposition is where mistakes are cheapest to fix and most expensive to leave, so
that is where deep human judgment is spent. by gates 1 and 2 the artifact is pinned
by tests and zero mutation survivors; the human is sampling taste and corridor, not
catching defects. that is the whole point of the forge: convert human attention into
automated rigor, concentrated at decomposition, then descending.

## gate 0 — the decomposition review (DEEP)

the foundational gate. everything downstream — cost, parallelism, survivor
localization, whether mutation even terminates — rides on it.

### 0a — task graph (after hardener)
the human inspects the breadth decomposition:
- are tasks atomic and genuinely independent (no shared mutable state)?
- do sibling corridors overlap? (overlap silently breaks survivor localization)
- are `mutation_budget`s realistic for the available CPU?
- are acceptance_criteria observable and falsifiable?
- is the dependency DAG acyclic and sane?
outcome: approve the graph, or send specific tasks back to the hardener.

### 0b — maximal behavior decomposition (after specifier PHASE 1)
the specifier HALTS after enumerating `behaviors[]`, before any Gherkin. the human
inspects the depth decomposition:
- is it exhaustive? every equivalence class, boundary, state, error path present?
- did the specifier reach the STOPPING RULE — is each behavior haiku-implementable in
  one pass (`min_tier: trivial`)? any `standard`/`complex` leaf must be split deeper.
- is the decomposition 3–5 levels deep, not a shallow restatement of the criteria?
- does every behavior trace to an acceptance_criterion (no orphans, no gaps)?
this is reviewed BEFORE pruning on purpose: pruning after an unreviewed decomposition
would hide gaps the human never saw. outcome: approve, or send the task back to the
specifier to decompose further.

## gate 1 — spot-check Gherkin (LIGHT)

the human samples scenarios across a few tasks (not all):
- do scenarios read as concrete, executable, in-corridor?
- did pruning drop anything load-bearing? (scan `prune_log` for `pruned` boundary/error scenarios)
- does every acceptance_criterion still have coverage?
a clean sample passes; a bad sample escalates that one task back to the specifier.

## gate 2 — spot-check code (LIGHT)

the human samples implemented modules:
- does the code read like the surrounding code? any smell the metrics missed?
- does it stay in corridor? any scope leak across task boundaries?
- the mutation report already proves the tests pin behavior — the human samples taste
  and corridor, not correctness.
a clean sample ships; otherwise route the specific module back to coder/refactorer.

## auto-escalation: when a light gate becomes deep

a light gate is promoted to deep review for a task when any of:
- the architect routed ≥ 1 unresolved survivor on that task
- a task hit `mutation_budget.exceeded = true`
- a stage handed off with `action: escalate` rather than green
- the specifier's prune_log shows a pruned boundary/error scenario
- any behavior shipped with `min_tier` worse than `trivial` (under-decomposed)
- gate 1 or 2 sampling found a corridor violation

auto-escalation is scoped to the offending task, never the whole pipeline. the
schedule still descends globally; one hot task does not re-heat the rest.
