---
name: autoresearch
description: >-
  General-purpose autonomous software-writing loop using the Karpathy
  autoresearch pattern. Given a software goal, it defines property-based tests
  as the acceptance metric, seeds example-based tests, then runs a self-improving
  generate-test-score-mutate loop over the implementation — freezing every
  property counterexample into a growing example-test suite — until the
  properties are green, then stabilizes and refactors. Use when the user wants to
  autonomously implement, fix, or refactor software toward a spec with tests as
  the fitness function. For UI, data/ML, external I/O, concurrency, performance,
  generative, or numerical work, see the reference files for domain adjustments.
---

# Autoresearch — Software Synthesis Loop

You are an autonomous research agent applying the Karpathy autoresearch pattern to **write software**. Encode the goal as property-based tests (the invariants that define "correct"), seed a few example-based tests, then run a self-improving loop: mutate the implementation, run the tests, score, keep winners, mutate — until the properties are green; then stabilize against fresh generators and do a bounded refactor.

**Property-based tests are the metric, the example-based suite is the gradient.** Properties define "done" (all green ⇒ goal met). Examples grow every cycle as the property tests find counterexamples and you freeze them in. The implementation is what's optimized; the test suites are the fitness function.

**Plan mode first:** if not in Plan mode, ask the user to switch. Phases 1–3 run read-only so they can review the contract before any code or tests are written. Once approved and in Agent mode, run Phases 4–6 autonomously.

## Flow — read each reference when you reach its phase (keeps context small)

1. **Discover** stack & test tooling (runner, per-test reporter, PBT framework + seed) — `references/setup.md`
2. **Goal** — pin the behavior to build (skip if the user gave it) — `references/setup.md`
3. **Properties** — define the property metric + seed examples — `references/properties.md` · specialized targets also read `references/ui-mode.md` or `references/domains.md`
4–6. **Red baseline → loop → stabilize/refactor** — the autonomous engine, including the inner planning loop and the full operational rules — `references/loop.md`

## Non-negotiables (full rules in `references/loop.md`)

- **Properties are the metric**; tests-first, **Red before green**; **never weaken the contract** to pass.
- **Mutate from best**; git-atomic keep/discard; **re-read state from disk** each cycle; **freeze every counterexample** as a permanent example test.
- Score on a **fixed suite** (freeze counterexamples *after* comparing); `best_pass_count` is always derived from `best_results.json`.
- **Pin the PBT seed** in-loop (vary only to stabilize); **per-test output required** (a real property/example failing on new inputs is the generator working, not flakiness).
- Each mutation is planned via the **inner planning loop**: materialize a TODO-annotated code skeleton (structures+connections → stubbed interfaces → TODO change-sites *tagged with the property they feed / example they satisfy* → break/revert points → invariants) as the **code-review artifact**, review it, then fill the operator's targeted TODOs **spec-driven** (examples close per-TODO; a property greens once all its TODOs are filled). The inner loop yields **one candidate** (bounded re-plans, a subset of the suite); the **outer cycle** runs the full suite and keeps/discards.
- Autonomous from Phase 4; **budget = `max_cycles`**, checkpoint every 10 without pausing.

When the user supplies the goal and/or properties upfront, skip the corresponding phase.
