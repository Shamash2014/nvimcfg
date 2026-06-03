# evals — how to test this skill

two layers: (1) skill-activation evals (does cog trigger and behave at the meta
level), (2) pipeline evals (does an instantiated pipeline obey its own contracts and
invariants). plus a self-audit checklist a reviewer or CI runs against the skill.

## 1. skill-activation evals

### should activate (≥ 3)
- "design an agent pipeline that turns my rough spec notes into tested code" → cog
- "I want Gherkin → acceptance tests → mutation testing, with cheap models doing the
  coding. how do I structure the decomposition?" → cog
- "my mutation tests are too CPU-heavy to finish — how do I decompose so they fit?" → cog
- "build a self-improving, vendor-agnostic spec-to-code system that resists
  sycophancy" → cog

### should NOT activate
- "write a regex that validates an email" → plain task, no pipeline. respond normally.
- "what's the CRAP metric?" → a definition question; answer directly, don't spin up
  the pipeline.

### edge / failure
- "decompose this but skip the tests, just give me code fast" → cog must REFUSE the
  tests-before-code violation, not comply. activation is correct; obeying the ask is not.

## 2. pipeline evals (instantiated system)

seed datasets per the cog substrate (eval-framework.md):
- 10–15 gold cases (locked), 200–300 synthetic, sycophancy-probe subset.
- forge-specific gold: each gold case carries the expected task DAG shape, the
  expected behavior count band, and the expected mutation_score (= 1.0).

hard-gate metrics (a run FAILS if any is off): mutation_score = 1.0,
gherkin_mutation_score = 1.0, crap_max ≤ 6, duplication_blocks = 0,
criterion_coverage = 1.0, corridor_compliance = 1.0, green_gate_integrity = 1.0.
quality signal: trivial_leaf_rate ≥ 0.90, decomposition_depth ∈ [3,5].

## 3. self-audit checklist (run against the skill itself)

contracts:
- [ ] every stage names an input contract and an output contract that exist in contracts/
- [ ] every JSON schema parses (`python3 -c "import json;json.load(open(f))"`)
- [ ] the GATE 0b halt validates against decomposition.schema.json (NOT gherkin.schema.json)
- [ ] handoff.human_gate.gate enum matches the gates the prompts emit (0a, 0b, 1, 2)

invariants (each must be enforced by at least one prompt + checkable by a metric):
- [ ] monotonic formality — no stage down-converts a formal artifact
- [ ] tests before code — coder writes acceptance→unit→code; code-first = abstain
- [ ] green-gate handoff — green==true only when verified (green_gate_integrity = 1.0)
- [ ] survivors route, not reset — mutation-report.remediation_routes name one task each
- [ ] decreasing human-heat — gate depth non-increasing (deep 0a,0b → light 1,2)
- [ ] decomposition is sacred — no stage merges tasks; stopping rule = haiku-implementable

cross-references:
- [ ] no stale stage names (decomposer/converter/executor/aggregator/subtask)
- [ ] no stale gate labels (GATE A/B/C)
- [ ] SKILL.md links resolve to files that exist

## 3b. pressure tests (writing-skills RED/GREEN)

cog's discipline-enforcing prompts must hold under pressure. See
[pressure-tests.md](pressure-tests.md) for the RED/GREEN/REFACTOR record,
rationalization table, and red-flags list. Re-run when MASTER or a discipline stage
prompt (02-coder, 03-refactorer, 04-architect) changes.

## 4. smoke test (one tiny spec end-to-end)

informal spec: "a function that clamps an integer to a [lo, hi] range."

expected pipeline behavior:
1. hardener → 1 task (atomic already), mutation_budget small, corridor = {in: clamp;
   out: floats, non-integer, range validation}.
2. specifier PHASE 1 → behaviors: below-lo→lo, above-hi→hi, in-range→unchanged,
   lo==hi, lo>hi (error path). all min_tier: trivial. HALT → gate 0b.
3. (after 0b) PHASE 2–3 → 5 scenarios, prune none (all distinct classes).
4. coder → acceptance test per scenario (red) → unit tests (red) → clamp() → green.
5. refactorer → crap_max ≤ 6 trivially; property test: result always in [lo,hi]
   when lo≤hi; idempotence clamp(clamp(x))==clamp(x). green.
6. architect → mutate `<`/`<=`, swap lo/hi, drop a branch → all killed by the boundary
   scenarios; gherkin mutation (drop the lo==hi Then) → killed. 0 survivors → gate 2.

pass = 0 survivors, crap ≤ 6, every behavior trivial, no routed remediation. if any
boundary scenario was pruned in step 3, expect a survivor in step 6 routing back to
the specifier — that is the localization property working.
