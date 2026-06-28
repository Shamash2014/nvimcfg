# Per-handoff autoresearch loop (Cog3 Phase 4 engine)

This replaces a plain single red-green-refactor cycle with an autonomous **property-as-metric** loop, run **once per approved handoff**. The handoff's properties are the acceptance metric; its Gherkin scenario(s) seed the example suite; every property counterexample is frozen into a permanent example test. The implementation is what gets optimized; the test suites are the fitness function.

Scope discipline is inherited from Cog2: the loop touches only the handoff's target surface and its tests, never pulls in other handoffs' scenarios, and stops to re-approve if it discovers a new behavioral delta (atomicity violation).

## State (per handoff, under `docs/cog3/<plan-slug>/tasks/<NN>-<slug>/.loop/`)

- `best_results.json` — best impl's per-test vector over the **current** suite: `{ "properties": {...bool}, "examples": {...bool} }`.
- `state.json`:
  ```json
  {
    "handoff": "<NN>-<slug>", "surface": "...", "test_cmd": "...", "reporter": "...",
    "pbt_seed": 1234, "property_count": 0, "example_count": 0,
    "best_pass_count": -1, "best_all_green": false, "green_streak": 0,
    "phase": "correctness", "run_number": 0, "plateau_counter": 0,
    "max_cycles": 20, "best_commit": null
  }
  ```
- `results.jsonl` — one line per cycle.

`pbt_seed` is pinned so in-loop runs are reproducible; vary it only in Stabilize. `max_cycles` is the per-handoff budget. Disk is the source of truth — re-read every cycle.

## Red baseline (run 0)

Write the handoff's property tests **and** its Gherkin scenario(s) as seed example tests **before** any implementation; commit. Run the suite — it MUST fail. A property that passes against a stub is too weak: strengthen it (and surface to the Cog2 handoff record) before continuing. Record `best_results.json`, `best_commit = HEAD`. **Cycle invariant: at the start of every cycle the working tree equals `best_commit`.**

## One cycle (correctness phase)

1. **Load** `state.json`, `best_results.json`, last 5 `results.jsonl`. Confirm tree == `best_commit`.
2. **Select operator + mutate** (state-dependent, not round-robin), mutating from best:
   - examples failing → *pass-the-simplest-failure* or *generalize-from-counterexample*
   - examples pass, a property still fails on a region → *strengthen-then-satisfy*
   - generators keep hitting a boundary → *edge-hardening*

   **Inner planning loop — materialize a reviewable TODO skeleton, then fill it.** Steps 1–6 plan one mutation *in code, not prose*: structures+connections, stubbed interfaces, a `TODO(...)` at every change site, marked break/revert points, invariant checks — a **TODO-annotated skeleton that is the code-review artifact.** Review it (self, a reviewer/code-review adapter, or the user) before writing logic; then implement **spec-first** — fill each reviewed TODO by driving its tagged property/example spec to green (the property loop, per TODO), looping back into planning whenever a TODO reveals a missing/wrong element, until green. The materialized TODOs are the work-list the property/spec loop consumes. Full for the first green, large extensions, and plateau-break rewrites; a small mutation re-plans only the relevant layer.
   1. **Structures + connections** — define/extend the structs/types **and the connections among them** (ownership, references, dependencies, data-flow edges, wiring) before logic.
   2. **Interfaces** — declare function/class signatures as stubs (`todo!()` / `raise NotImplementedError` / `throw`) so Red fails on *behavior*, not a compile/import error.
   3. **TODO change-sites** — drop a tracked TODO at every site the change touches, **tagged with the property/example it satisfies** (`TODO(<NN>-<slug> → P2/E3): …`); these markers *are* the materialized plan, the unit a reviewer reads, and the spec each fill is driven by.
   4. **Break + revert points** — mark where the change must break existing code (shared signature/schema/caller); make the break inside the git-atomic cycle so a DISCARD restores it cleanly; never leave the tree half-broken across a KEEP. This also forces a Cog2 atomicity recheck — if the break spans another behavioral delta, stop and split the handoff.
   5. **Invariants + defensive checks** — internal preconditions/postconditions/structural asserts that complement the property tests (never replace one).
   6. **Implement — spec-driven, per TODO** — fill each reviewed TODO by driving its tagged property/example to green (watch it fail, fill until it passes; a TODO closes only when its spec is green). Loop back to 1 if the skeleton proves wrong, until green.
3. **Run** with the pinned `pbt_seed` and a per-test reporter (JSON/JUnit/TAP). Parse `V_cur = {properties, examples}` (which pass). Capture each failed property's **shrunk counterexample**.
4. **Score on the current suite `S` vs `best_results`:**
   ```
   no_regress  = every property/example true in best_results is also true in V_cur
   gain        = count(true in V_cur) > best_pass_count            # same suite S
   first_green = (all properties true in V_cur) AND not best_all_green
   KEEP if first_green OR (gain AND no_regress) else DISCARD
   ```
5. **Apply:**
   - KEEP → `git commit`; `best_commit=HEAD`; `best_results=V_cur`; `best_all_green = all props green`; `plateau_counter=0`.
   - DISCARD → `git restore` to `best_commit`; `plateau_counter += 1`.
6. **Freeze counterexamples (AFTER step 4):** for each failed property, add its shrunk counterexample as a named example test (tagged `counterexample@run<N>`), suite `S→S'`. Run **only the new tests** against the current tree (== best) and append to `best_results.examples`; bump `example_count`. Then **recompute `best_pass_count` = count of `true` in `best_results`** over `S'` (always derived, never stale), so next cycle's `gain` compares on the same denominator.
7. **Log + update state** (`run_number`, `best_pass_count`, `best_all_green`, `plateau_counter`, `example_count`, `best_commit`).
8. **Report** one line. If `best_all_green` just became true → `phase = "stabilize"`.
9. **Plateau breaker:** `plateau_counter == 5` → don't mutate from best; rewrite the implementation from scratch using only the handoff outcome, properties, and accumulated counterexamples; score with the same step-4 rule; log `plateau_break`; reset counter.
10. **Budget:** checkpoint every 10 cycles without pausing; if `run_number >= max_cycles`, stop the handoff with a "budget reached" status and report it to the Cog2 goal ledger (do not silently mark complete).

## Stabilize → Refactor (once properties green)

- **Stabilize** (`phase: stabilize`): no mutation; re-run best with a **new seed** each run. Green again → `green_streak += 1`; a surfaced counterexample → freeze it, `best_all_green=false`, `green_streak=0`, back to correctness. At `green_streak == 3` → `phase: refactor`.
- **Refactor** (`phase: refactor`, ≤ 3 cycles): apply refactor-green (simplify, no behavior change). KEEP iff all properties green AND all examples pass (pinned seed) AND complexity not worse (LOC / cyclomatic); else DISCARD. Then the handoff is done.

## Handoff completion → back to Cog2

A handoff is complete only when: all its properties are green and stable across 3 seeds, every seed/regression example passes, the red baseline showed a genuine failure first, and the refactor pass left the suite green. Record into the handoff `.md`: red evidence, property+example pass vectors, counterexamples frozen (count + inputs), seeds used, files changed, and any budget/atomicity deviation. Then advance the Cog2 goal ledger to the next handoff.

## Anti-gaming (inherited, absolute)

Never weaken a property, delete an example, or special-case the implementation to a known test input to manufacture a gain. Properties may only be *strengthened*. A property failing on inputs an earlier run didn't generate is the generator working — freeze the counterexample; that is not flakiness. True flakiness (same pinned input, different result) is red until stabilized.
