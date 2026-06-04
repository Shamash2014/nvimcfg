# the human-heat schedule

human involvement is a temperature. it is FRONT-LOADED on the plan — decomposition is
the load-bearing act — and then descends. there are two human gates; the plan gate is
deep, the code gate is light. depth only ever decreases, never rises (the
decreasing-human-heat invariant).

```
gate plan   PLAN REVIEW       DEEP  — after stages 0+1 run silently: review the task
                                      graph (breadth) + maximal behavior decomposition
                                      (depth) + pruned Gherkin + prune_log, all at once
gate 2      after architect   LIGHT — spot-check a sample of code
```

decomposition is where mistakes are cheapest to fix and most expensive to leave, so
that is where deep human judgment is spent. by gate 2 the artifact is pinned by tests
and zero mutation survivors; the human is sampling taste and corridor, not catching
defects. that is the whole point of the forge: convert human attention into automated
rigor, concentrated at the plan, then descending.

## gate plan — the plan review (DEEP)

the foundational gate. stages 0 (hardener) and 1 (specifier) run silently — no halt
between them — then the orchestrator presents ONE consolidated plan and STOPS for a
single verdict. everything downstream — cost, parallelism, survivor localization,
whether mutation even terminates — rides on this one review. nothing self-approves;
no code is written until the human accepts the plan.

what the human reviews, in one sitting:

### breadth — the task graph (from the hardener)
- are tasks atomic and genuinely independent (no shared mutable state)?
- do sibling corridors overlap? (overlap silently breaks survivor localization)
- are `mutation_budget`s realistic for the available CPU?
- are acceptance_criteria observable and falsifiable?
- is the dependency DAG acyclic and sane?

### depth — the maximal behavior decomposition (from specifier PHASE 1)
- is it exhaustive? every equivalence class, boundary, state, error path present?
- did the specifier reach the STOPPING RULE — is each behavior haiku-implementable in
  one pass (`min_tier: trivial`)? any `standard`/`complex` leaf must be split deeper.
- is the decomposition 3–5 levels deep, not a shallow restatement of the criteria?
- does every behavior trace to an acceptance_criterion (no orphans, no gaps)?

### formalization — the pruned Gherkin + prune_log (from specifier PHASE 2–3)
- do scenarios read as concrete, executable, in-corridor?
- does every acceptance_criterion still have coverage in `coverage_map`?
- did pruning drop anything load-bearing? scan `prune_log` for `pruned` boundary/error
  scenarios. the prune_log is presented WITH the full `behaviors[]` precisely so a
  dropped behavior is visible here — that is what replaces a separate pre-prune halt.

outcome: approve the whole plan, or send specific tasks back — to the hardener (bad
breadth), the specifier PHASE 1 (under-decomposed depth), or the specifier PHASE 2–3
(bad/over-aggressive Gherkin). only the offending task is sent back, not the whole run.

## gate 2 — spot-check code (LIGHT)

after stages 2 → 3 → 4 have run autonomously, the human samples implemented modules:
- does the code read like the surrounding code? any smell the metrics missed?
- does it stay in corridor? any scope leak across task boundaries?
- the mutation report already proves the tests pin behavior — the human samples taste
  and corridor, not correctness.
a clean sample ships; otherwise route the specific module back to coder/refactorer.

## auto-escalation: when the light gate becomes deep

gate 2 is promoted to deep review for a task when any of:
- the architect routed ≥ 1 unresolved survivor on that task
- a task hit `mutation_budget.exceeded = true`
- a stage handed off with `action: escalate` rather than green
- the specifier's prune_log shows a pruned boundary/error scenario
- any behavior shipped with `min_tier` worse than `trivial` (under-decomposed)
- gate 2 sampling found a corridor violation

auto-escalation is scoped to the offending task, never the whole pipeline. the
schedule still descends globally; one hot task does not re-heat the rest.
