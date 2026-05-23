---
name: cog
description: Apply the decomposition-and-contract LLM pipeline pattern — anti-sycophancy master prompt, per-stage prompts (decomposer / md→json converter / focused executor / aggregator / eval / meta self-learning), JSON contracts, and eval framework with gold + synthetic + sycophancy probes. Use when designing or hardening any multi-step LLM or agent system, fighting sycophancy / hallucinations / scope-creep / verbosity, building vendor-agnostic and domain-agnostic AI architectures, or when the user mentions "cog", "cogitate", "anti-sycophancy", "decomposition pipeline", "AI-native OS", "cognitive infrastructure", "self-improving framework", or asks how to make LLM systems stable, testable, and reproducible.
---

# cog

vendor-agnostic. domain-agnostic. self-improving.
not a workflow. not LangChain. an engineering discipline.

## when to invoke

- user wants to design a multi-step LLM / agent system
- user complains: sycophancy, hallucinations, instability, prompt rot, vendor lock-in
- user asks for a self-improving eval-driven AI architecture
- user is about to dump a giant monolithic prompt — intercept and decompose
- user mentions: "decomposition", "contracts between agents", "JSON pipeline", "AI OS", "cognitive layer"

## core idea

complexity is NOT solved inside model context. complexity is decomposed OUT into narrow subtasks with strict JSON contracts. every prompt = data contract (corridor + criteria + metrics + output schema). every output is scored. winning prompt variants get promoted by a meta-learner.

## the 6 stages

```
user_md → [0] decomposer → [1] md→json → [2] executor → [3] aggregator → output
                                                              │
                                          [4] eval ←──────────┘
                                            │
                                          [5] meta-learner → prompt_version++
```

## the 4 layers (orthogonal, replaceable)

- **L1 reasoning** — LLM calls. swappable model.
- **L2 contracts** — JSON schemas. process-free.
- **L3 control** — orchestration, routing, eval gate.
- **L4 knowledge** — domain prompts, RAG, KG, datasets. vertical lives here only.

## how to use this skill

### 1. drop the master prompt
Read [prompts/MASTER.md](prompts/MASTER.md). The block between `---` lines is the system prompt for every LLM call in the pipeline. It enforces anti-sycophancy, JSON-only output, scope discipline, calibrated confidence, and abstain-on-uncertainty.

### 2. specialize per stage
Each stage inherits MASTER and adds narrow rules:
- [prompts/00-decomposer.md](prompts/00-decomposer.md) — splits task into 5–10 children, recurse until atomic
- [prompts/01-converter.md](prompts/01-converter.md) — cheap model, md → strict Subtask JSON
- [prompts/02-executor.md](prompts/02-executor.md) — one atomic subtask, one focused output
- [prompts/03-aggregator.md](prompts/03-aggregator.md) — merges typed child results, no synthesis
- [prompts/04-eval.md](prompts/04-eval.md) — judge one (case, response) pair
- [prompts/05-meta-learning.md](prompts/05-meta-learning.md) — generates candidate prompt variants from regressions

### 3. wire the contracts
Every stage input / output validates against a schema:
- [contracts/task.schema.json](contracts/task.schema.json) — recursive decomposed task tree
- [contracts/subtask.schema.json](contracts/subtask.schema.json) — atomic leaf with corridor + criteria + metrics + output_schema
- [contracts/result.schema.json](contracts/result.schema.json) — execution result with confidence, disagreement, action (`answer | ask | escalate | abstain`), trace
- [contracts/eval.schema.json](contracts/eval.schema.json) — eval report with deltas, regressions, wins, verdict

Validation failure = retry once, then abstain. Never paper over.

### 4. seed eval
- 10–15 hand-curated **gold** cases (locked, regression here = block deploy)
- 200–300 **synthetic** cases (regenerated weekly from real traffic patterns)
- subset of gold = **sycophancy probes** (engineered to elicit false agreement; correct disagreement = pass)
- metrics: correctness, faithfulness, sycophancy_resist, calibration_brier, corridor_compliance, cost, latency
- See [references/eval-framework.md](references/eval-framework.md) for thresholds and the self-learning loop.

### 5. enable meta-learning
Meta-learner runs in background. Generates ≤5 candidate variants per stage per cycle. Shadow-tests on synthetic. Promotes only if gold pass-rate ≥ baseline AND no metric regresses > 2% AND sycophancy_resist not worse. Keeps last 10 versions for rollback.

## anti-sycophancy enforcement

three layers of defense:

1. **prompt-level** — DISAGREEMENT_POLICY in MASTER forces grounded disagreement when user assertion contradicts inputs; banned-prefix list strips flattery
2. **post-processor** — runtime regex rejects responses containing banned tokens and reprompts with the violation in context
3. **eval-level** — `sycophancy_resist ≥ 0.90` threshold; sycophancy probes give binary pass/fail (no partial credit)

## grill pass (adversarial pressure test)

Before promoting prompt variants, run a dedicated "grill" pass inspired by `grill-me`:

1. pick the weakest stage/output (highest uncertainty, most hand-wavy rationale, or highest failure impact)
2. ask one hard adversarial question at a time (depth-first), e.g.:
   - what if this assumption is false?
   - why not the strongest alternative?
   - what breaks first at 10x scale / noisy inputs?
   - what is rollback when this stage fails?
3. require concrete evidence (tests, traces, citations, contract fields) — vague answers fail
4. do not move on until branch is resolved or explicitly parked with risk noted
5. summarize branches as `resolved | parked(risk) | failed`

Minimum grill checklist per candidate variant:
- failure modes identified for each stage touched
- contradiction check against contracts and corridor
- explicit rollback/recovery path
- at least one adversarial "user is wrong" probe passed
- no unresolved high-risk parked branches

Promotion gate update:
- candidate can only promote if it passes existing eval gate **and** grill checklist
- if grill fails, variant is quarantined with failure notes for next meta-learning cycle

## references

- [references/stages.md](references/stages.md) — full per-stage spec (rules, models, failure modes)
- [references/layers.md](references/layers.md) — L1–L4 separation of concerns
- [references/eval-framework.md](references/eval-framework.md) — datasets, metrics, self-learning gate, banned-tokens

## what NOT to do with this pattern

- don't dump everything into one giant prompt — defeats the entire decomposition premise
- don't skip contracts because "it's just a prototype" — contracts ARE the prototype
- don't let one model own the pipeline — route by tier so the system stays vendor-swappable
- don't add a "be helpful" instruction anywhere — that's how sycophancy leaks back in
- don't auto-promote variants without the gate — regressions compound silently
- don't expose chain-of-thought unless the contract has a `reasoning` field for it

## moat reminder

the model is not the moat. the L2/L3/L4 stack — contracts, eval datasets, feedback loops, accumulated operational knowledge — compounds over years while models commoditize in months.
