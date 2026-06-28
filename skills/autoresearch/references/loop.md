# Phases 4–6 — Red Baseline, the Loop, Stabilize/Refactor

## Phase 4 — Red Baseline + Loop Setup

### Set up state tracking

Create `.autoresearch/` in the repo root:

1. **`properties.md`** — the agreed properties (archetype + generator notes). The frozen acceptance contract.
2. **`examples.md`** — running log of example tests, each with input, expected output, and origin (`seed` | `counterexample@run<N>` | `regression`).
3. **`best_results.json`** — the per-test result vector of the current best implementation, over the *current* suite (makes regression detection computable without re-running best):
   ```json
   { "properties": {"P1": true, "P2": false}, "examples": {"E1": true, "E2": false} }
   ```
4. **`state.json`**:
   ```json
   {
     "goal": "[goal]", "surface": "[function/module]",
     "test_cmd": "[exact command]", "reporter": "[per-test output flag]",
     "pbt_seed": 1234, "property_count": 0, "example_count": 0,
     "best_pass_count": -1, "best_all_green": false, "green_streak": 0,
     "phase": "correctness", "run_number": 0, "plateau_counter": 0,
     "max_cycles": 30
   }
   ```
   `pbt_seed` is fixed so in-loop runs are reproducible. `max_cycles` is the autonomy budget (raise if the user asks). `phase` moves `correctness → stabilize → refactor`.
5. **`results.jsonl`** — empty; appended each cycle.

Add `.autoresearch/` to `.gitignore` if one exists and the entry is absent. **No git commits** — the loop runs entirely in the working tree. Keep a mirror of the best accepted state in `.autoresearch/best/` (the files the run touches); that snapshot is the no-git revert baseline. The final result is left as uncommitted working-tree changes for the user to review and commit.

### Write the tests first (red)

Write the property tests and seed example tests **before any implementation**. Run the suite — it MUST fail (red). If the properties pass against a stub, they are too weak; strengthen them first. A property that can't fail proves nothing.

### Baseline

Record the red baseline as **run 0**: 0 properties green, examples passing = whatever the stub satisfies (usually 0). Write `best_results.json`, set `best_pass_count` to the stub's example-pass count, and mirror the touched files into `.autoresearch/best/`. The tree is now best — invariant: **at the start of every cycle the working tree equals best (matches `.autoresearch/best/`).**

```
Red baseline (run 0): 0/[P] properties green · [k]/[E] examples passing
Working tree, no commits · Test cmd: [cmd] · Seed: [pbt_seed] · Budget: [max_cycles] cycles
```

## Phase 5 — The Loop (correctness phase)

Run autonomously, without asking permission between cycles. **Disk is the source of truth** — re-read `state.json`, `properties.md`, `examples.md`, `best_results.json`, and the last 5 lines of `results.jsonl` at the start of every cycle.

**Cycle invariant:** at step 1 the working tree equals best (mirrored in `.autoresearch/best/`), and `best_results.json` is its per-test vector over the **current** suite `S`. Scoring compares the mutated implementation against `best_results` on the *same* `S` — apples to apples. New counterexamples are frozen **after** the comparison, never during it, so the denominator never moves mid-comparison.

### One outer cycle

#### 1. Load state from disk
Read `state.json`, `examples.md`, `best_results.json`, last 5 `results.jsonl`. Confirm the working tree equals best (matches `.autoresearch/best/`).

#### 2. Select an operator and mutate (runs the inner planning loop)
Operator selection is **state-dependent, not round-robin** — pick what the current failures call for, and log it:
- examples failing → **pass-the-simplest-failure** or **generalize-from-counterexample**
- examples pass but a property still fails on a region → **strengthen-then-satisfy**
- generators keep hitting a boundary → **edge-hardening** (empty, null, zero, max, overflow, unicode, concurrency)
- (plateau-break and refactor-green are reached via steps 8–9 and Phase 6, not here.)

Always mutate **from best** (the tree already equals it). Produce the change via the **inner planning loop** below.

##### Inner planning loop — materialize a reviewable TODO skeleton, then fill it
Nested inside outer step 2: it produces **one candidate mutation** and does **not** run the outer scoring. Steps 1–6 plan the change *in code, not prose*: structures+connections, stubbed interfaces, a `TODO(...)` at every change site, marked break/revert points, invariant checks — a **TODO-annotated skeleton that is the code-review artifact** (review it — self, a reviewer/code-review adapter, or the user — *before* writing logic; design fixes are cheap here). Then fill **only the TODOs the chosen operator targets** (a subset — the rest of the suite may stay red; that's expected). The fill is **best-effort and bounded**: re-plan (loop to step 1) at most ~2–3 times if a TODO reveals a wrong skeleton element, then hand the candidate to outer step 3 **as-is** — the outer cycle runs the full suite once and decides KEEP/DISCARD (a candidate that didn't pan out is simply discarded; 5 discards in a row trigger the plateau-breaker). The materialized TODOs are the work-list the property/spec loop consumes. Full skeleton for the first green, large extensions, and plateau-break rewrites; a small mutation re-plans only the relevant layer. (Inner test runs aren't counted against `max_cycles`, which budgets outer cycles.)

1. **Structures + connections.** Define/extend the structs/types the behavior needs **and the connections among them** — ownership, references, dependencies, data-flow edges, wiring — before any logic.
2. **Interfaces.** Declare the function/class signatures (the contract surface) as stubs (`todo!()` / `raise NotImplementedError` / `throw`). Stubs make the Red test fail on *behavior*, not a compile/import error.
3. **TODO change-sites.** Drop a tracked TODO at every site the change touches, **tagged with the property it feeds or the example it satisfies** (`TODO(goal → P2/E3): …`) — these markers *are* the materialized plan, the unit a reviewer reads, and the spec each fill is driven by; the full blast radius is visible before any logic.
4. **Break + revert points.** Mark where the change must break existing code (a shared signature, schema, or caller); **track exactly which files you touch this candidate** so a DISCARD can restore them from `.autoresearch/best/` cleanly — never leave the tree half-broken once the candidate is kept. Land the smallest break the failing test needs.
5. **Invariants + defensive checks.** Add internal assertions — preconditions, postconditions, structural invariants — in the code itself. They complement the external property tests (catching what a generator may miss) and document intent; they never replace a property.
6. **Implement — spec-driven, per TODO.** Fill the TODOs the chosen operator targets, each driven by its tagged spec (watch it fail, fill until it passes). An **example**-tagged TODO closes when its example is green. A **property** is an *aggregate gate*: several TODOs usually feed it, so it greens only once all its contributing TODOs are filled — an individual property-tagged TODO is *planned-done* when its code is filled and reviewed, even if the property stays red pending siblings. **Implementation relies on green tests**: never treat a TODO as truly complete on filled-but-red code, and the candidate becomes best only when the outer per-test score is green/gain — there is no commit; green tests, not git, are what "keeps" the work. Re-plan (back to step 1) at most a couple of times if the skeleton proves wrong; then hand the candidate to outer step 3.

#### 3. Run the tests (evaluate)
Run the test command with the pinned `pbt_seed` and the per-test reporter. Parse a **per-test result map** `V_cur` = `{properties, examples}`. Exit code alone is insufficient. For each failed property, capture the **shrunk counterexample** (reproducible because the seed is pinned).

#### 4. Score and compare (on the current suite `S`, against `best_results`)
```
no_regress       = every property/example that best_results marks true is also true in V_cur
gain             = (count of true in V_cur) > best_pass_count          # same suite S
all_green        = every property AND every example in V_cur is true   # the FULL suite
first_full_green = all_green AND not best_all_green                    # best_all_green ≡ best is fully green
KEEP if  first_full_green OR (gain AND no_regress)  else  DISCARD
# Note: transition to stabilize requires the full suite green, never properties-only — so no red
# example (regressed or orthogonal-and-never-passed) can sneak into stabilize. all_green subsumes
# no-example-regress. An example the properties don't imply just keeps the loop in correctness
# (mutating to satisfy it) until it greens or the budget stops it — never a stuck stabilize.
```

#### 5. Apply keep/discard
```
KEEP (green tests say so — no commit):
         mirror the touched files into .autoresearch/best/; best_results=V_cur; best_all_green = all_green (full suite); plateau_counter=0
DISCARD: restore the touched files from .autoresearch/best/ (undo this candidate); plateau_counter += 1
```

#### 6. Freeze counterexamples (AFTER the comparison)
For each property that failed in `V_cur`, add its shrunk counterexample as a new example test (named, tagged `counterexample@run<N>`). Suite grows `S → S'`. Run **only the newly added tests** against the current tree (== best) and append pass/fail to `best_results.examples`; bump `example_count`. Then **recompute `best_pass_count` = count of `true` in `best_results`** over `S'` (always derived, never stale).

#### 7. Log + update state
Append one JSON line to `.autoresearch/results.jsonl`:
```json
{ "run": 1, "timestamp": "ISO 8601", "phase": "correctness",
  "properties_green": 0, "property_total": 0, "examples_passing": 0, "example_total": 0,
  "status": "keep | discard",
  "mutation_operator": "pass_simplest_failure | generalize_counterexample | strengthen_then_satisfy | edge_hardening | plateau_break | refactor_green",
  "new_counterexamples": ["shrunk input frozen into an example test"],
  "failures": ["brief: which property/example failed and why"], "files": ["files touched this candidate"] }
```
Update `state.json` (`run_number`, `best_pass_count`, `best_all_green`, `plateau_counter`, `example_count`).

#### 8. Report + transition
`RUN [n] | Props: [g]/[P] | Examples: [k]/[E] | Status: [KEEP/DISCARD] | Best pass: [bp]` + mutation + new counterexamples + top failures. If `best_all_green` just became true → `phase = "stabilize"` and go to Phase 6.

#### 9. Plateau breaker
If `plateau_counter` reaches 5 (5 cycles, no KEEP): don't mutate from best. Re-read the last 10 `results.jsonl` entries and **rewrite the implementation from scratch** (running the inner planning loop) using only the goal, properties, and accumulated counterexamples — ignore the stuck structure. Score with the same step-4 rule. Log `plateau_break`; reset `plateau_counter = 0`.

#### 10. Budget + continue
Every 10 cycles, print a checkpoint (best pass count, properties green, top failures) without pausing. If `run_number >= max_cycles`, stop with a "budget reached" report. Otherwise go to step 1.

## Phase 6 — Stabilize, then Refactor (once the full suite is green)

### Stabilize (`phase: "stabilize"`)
Do **not** mutate. Re-run the **full suite** (properties + examples) against best with a **new, different PBT seed** each run. **Green = the entire suite passes.**
- Fully green again → `green_streak += 1`.
- A run surfaces a property **counterexample**, *or* a previously-green **example** goes red → it's a real residual regression: freeze the counterexample (if any), set `best_all_green=false`, `green_streak=0`, `phase="correctness"`, return to Phase 5 to fix it.

When `green_streak` reaches **3** (three distinct seeds, all fully green) → set `phase = "refactor"`.

### Refactor (`phase: "refactor"`, bounded — default ≤ 3 cycles)
Apply **refactor-green** (simplify, no behavior change) via the inner planning loop. Because correctness is maxed (gain impossible), use a different KEEP rule:
```
KEEP if  all properties green AND all examples pass (pinned seed) AND complexity not worse (LOC, or cyclomatic if a tool exists)
else DISCARD (restore touched files from .autoresearch/best/)
```
After the refactor budget is spent (or two consecutive DISCARDs), **stop**.

### Final report
```
AUTORESEARCH COMPLETE
  Goal: [goal]   ·   Runs: [total]   ·   Phase reached: refactor
  Properties: [P]/[P] green, stable across [green_streak] seeds
  Examples:   [E]/[E] passing  ([E_start] → [E] grown from counterexamples)
  Counterexamples frozen into regressions: [count]
  Most effective operators: [ranked by KEEP rate]
Implementation: [files changed]  ·  Tests: [test files]  ·  Result: uncommitted working-tree changes (no commits)  ·  History: .autoresearch/results.jsonl
```

## Operational Rules

1. **Properties are the metric.** All properties green, stable across 3 distinct seeds, is the only definition of done.
2. **Examples are the gradient.** Every property counterexample is frozen into a permanent example test. The suite only grows.
3. **Never weaken the contract to pass.** Don't loosen a property, delete an example, or special-case to a known test input. Strengthen properties; never weaken them.
4. **Tests first, red before green.** Confirm the tests fail for the intended reason first. A property that can't fail is rejected as too weak.
5. **Score on a fixed suite, freeze after.** Compare against `best_results` on the same `S`; freeze counterexamples only after deciding keep/discard. Never compare across a changed denominator.
6. **Mutate from best**, never from a discarded attempt. Invariant: the working tree equals best (the `.autoresearch/best/` snapshot) at step 1.
7. **Persist per-test results.** `best_results.json` holds best's vector; extend it (run only new tests) when the suite grows. `best_pass_count` is always the derived count of `true` in `best_results` — recompute after every growth.
8. **Re-read state from disk every cycle.** Conversational memory is not trusted for state, scores, or counterexamples.
9. **No git commits.** The loop runs in the working tree; KEEP mirrors the green change into `.autoresearch/best/`, DISCARD restores from it. **Implementation relies on green tests** — a change is "kept" only when the outer per-test score is green/gain, never via a commit. Leave the final result as uncommitted changes for the user to review/commit.
10. **Pin the PBT seed in the loop; vary it only to stabilize.** A property failing on inputs an earlier run didn't generate is the generator working — freeze the counterexample, don't call it flaky. True flakiness (same pinned input, different result) is red until stabilized.
11. **Need per-test output.** Use a JSON/JUnit/TAP reporter (or run tests by name); exit code can't tell you how many properties/examples passed.
12. **Refactor only in Phase 6**, with the complexity-not-worse rule — never in the correctness phase.
13. **Respect the budget.** Every run — correctness, stabilize, or refactor — increments `run_number` and counts toward `max_cycles`; stop at `max_cycles`. Checkpoint every 10 runs without pausing.
14. **Stay scoped.** Modify only the target surface and its tests.
15. **Log everything** — every cycle gets a JSONL entry with counterexamples and the operator used.
16. **Inner planning loop** yields one candidate mutation per outer cycle (it does not score): materialize a TODO-annotated code skeleton (structures+connections → stubbed interfaces → TODO change-sites *tagged with the property they feed or example they satisfy* → break/revert points → invariants/defensive checks) as the **code-review artifact**, review it, then fill the operator's targeted TODOs spec-driven — example-tagged TODOs close when their example greens; a property is an aggregate gate (greens only when all its contributing TODOs are filled). Re-plan at most a couple of times, then hand the candidate to the outer run/score (steps 3–6), which keeps or discards. Internal invariants complement, never replace, the property tests.
17. **Specialized domains:** read `ui-mode.md` (frontend) or `domains.md` (data/ML, external I/O, concurrency, performance, generative, numerical) before writing properties. The golden-approval checkpoint in UI mode is the *only* sanctioned pause to autonomy; any llm-judge is advisory and never gates KEEP/DISCARD.
