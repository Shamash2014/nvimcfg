---
name: cog2
description: Runs a provider-agnostic Socratic spec-to-code workflow that resolves a plan, explores the target codebase, decomposes work into atomic two-file handoffs (one focused Gherkin scenario plus one Markdown execution contract), tracks the goal through native tools or a portable ledger, and implements each behavior with observed red-green-refactor TDD. Use when the user mentions cog2, asks to turn a plan into tested code, wants assumptions surfaced before implementation, or requests repository-grounded Gherkin, task handoffs, and TDD execution across any agent provider.
---

# Cog2

## Goal

Turn an informal plan into verified code without guessing. Move through four strict phases:

1. Socratic convergence
2. Codebase exploration
3. Gherkin and task decomposition
4. Red-green-refactor execution

Execute the workflow; do not merely describe it.

Invoking Cog2 is an explicit request to enter goal mode. Before Phase 1, initialize goal tracking with the first available adapter:

1. Native goal API: create a goal with the user's requested outcome. Do not set a token budget unless the user supplied one.
2. Persistent task or plan API: create one top-level tracked item and keep it active.
3. Portable fallback: emit a `Goal Ledger` containing the objective, status `active`, current phase, completed handoffs, pending handoffs, and blockers. Repeat the updated ledger at every phase gate and in the final report. After repository editing is approved, persist it at `docs/cog2/<plan-slug>/goal.md` with the handoffs.

Never skip goal mode because a provider lacks a named goal tool. Keep the goal active through both human gates and all task handoffs. Mark it complete through the selected adapter only after every completion condition is verified.

Treat provider features as adapters, not workflow semantics. Do not assume tool names, skill invocation syntax, model names, subagent support, planning APIs, usage metrics, or filesystem APIs. Discover available capabilities, map them to the required operation, and use the portable conversational or file-based fallback when absent. If a provider cannot read, write, or execute repository commands, complete the interview and handoff plan, keep the goal active, and report the missing execution capability as the blocker.

## Core Rules

- Ask one question per user turn during the interview.
- Lead with questions that expose assumptions, consequences, evidence, and edge cases. Do not answer the design question for the user when a question can help them derive it.
- Resolve one decision branch depth-first before opening another.
- Treat vague answers as unresolved. Ask for an example, invariant, threshold, failure policy, or explicit tradeoff.
- Never invent requirements. Record unresolved items as parked, with their implementation risk.
- Do not inspect or edit the repository until the user confirms the shared-understanding summary.
- Do not write production code until the user approves the repository-grounded Gherkin plan.
- Do not write production code without first running a test and observing the expected failure.
- Represent every implementation task as exactly two handoff files: one `.feature` file containing one focused scenario and one `.md` file containing its execution contract.
- Embed `Required execution discipline: test-first red-green-refactor` in every task handoff. If a matching TDD skill is installed, name it as an optional adapter; otherwise execute the discipline directly from this skill.
- Select the narrowest available specialist skill or capability when one materially helps the task. Never invent a skill, tool, model, or provider name, and never make task completion depend on an optional provider integration.
- Do not combine independent behaviors, boundary outcomes, or failure policies in one handoff. Split them into dependency-ordered tasks.
- Require each handoff to state its exact executable assertions: assertion subject, framework-native matcher, concrete expected value, and failure message or diff expected during Red. Reject vague assertions such as "works", "is valid", "returns correctly", broad snapshots, or truthiness when a precise value can be asserted.
- Preserve existing repository patterns and unrelated user changes.

## Phase 1: Socratic Convergence

Start from the user's informal plan. If none exists, ask for it.

Silently build a decision tree covering at least:

- desired outcome and observable success
- users, actors, and entry points
- scope and explicit non-goals
- inputs, outputs, state, and invariants
- happy path, edge cases, and failure behavior
- compatibility, migration, rollout, and rollback
- security, privacy, performance, and operational constraints when relevant
- verification and acceptance criteria

Choose the highest-risk unresolved branch and ask one concise question. Prefer questions such as:

- What assumption makes that choice valid?
- What observable result would distinguish success from partial success?
- What happens at the boundary or failure case?
- Which existing behavior must remain unchanged?
- Why is this option preferable to the strongest alternative?
- What evidence would falsify this decision?

After each answer:

1. Restate the resolved decision briefly.
2. Note any dependency it unlocks.
3. Ask the next single question.
4. Periodically report resolved, unresolved, and parked branch counts.

When all material branches are resolved or explicitly parked, present a shared-understanding summary using `references/templates.md`. Ask the user to confirm or correct it. Stop. Do not enter Phase 2 without explicit confirmation.

## Phase 2: Explore the Codebase

After confirmation, inspect before designing:

1. Read repository guidance and determine language, framework, build, test, lint, and formatting commands.
2. Map relevant entry points, modules, callers, callees, data flow, state transitions, side effects, and public contracts.
3. Read relevant files end-to-end, including neighboring tests and fixtures.
4. Search for analogous implementations and established local patterns.
5. Inspect relevant history with `git log`, `git show`, or `git blame` when intent is unclear.
6. Check worktree status and preserve unrelated changes.
7. Run the narrowest useful baseline tests when practical.

Produce a concise evidence map:

- affected behavior and current flow
- likely files and ownership boundaries
- reusable patterns and test infrastructure
- constraints discovered in code
- contradictions between the plan and repository reality
- remaining questions or risks

If exploration invalidates a confirmed decision, return to Phase 1 for that branch only. Ask one Socratic question and reconfirm the amended summary before proceeding.

## Phase 3: Gherkin and Task Decomposition

Translate the confirmed intent and repository evidence into example-based requirements.

Write Gherkin where each scenario has:

- one distinct behavior
- concrete preconditions
- a triggering action
- observable outcomes
- boundary or failure examples where behavior differs

Make every `Then` concrete enough to translate directly into one or more exact test assertions. Name the observable value, state transition, emitted effect, error type/message, count, ordering, or absence being asserted. Do not use `Then it succeeds`, `Then it works`, or equivalent placeholders.

Avoid implementation details unless they are part of the public contract. Prune duplicate scenarios only when they exercise the same equivalence class and outcome; record why. If a feature needs multiple scenarios, create multiple task handoffs. A `Scenario Outline` is allowed only when every example exercises the same behavior, path, and expected outcome shape.

Decompose implementation into the smallest dependency-ordered tasks that can complete one red-green-refactor cycle. For each task, create a handoff preview from `references/templates.md` containing:

- `<NN>-<slug>.feature`: exactly one `Feature` and exactly one focused `Scenario` or `Scenario Outline`
- `<NN>-<slug>.md`: the task identity, outcome, dependencies, repository evidence, expected files, exact assertions, red test and failure, minimal green target, verification commands, non-goals, and completion evidence
- `Required execution discipline: test-first red-green-refactor`
- `TDD adapter: <provider-native skill identifier> | native instructions`
- `Specialist adapter: <provider-native skill identifier> | <available capability> | none`

Choose adapters by inspecting the current provider's available skills and tools. Prefer the narrowest installed skill whose stated trigger directly matches the work, then a matching native capability, then `none`. The TDD discipline governs implementation order regardless of adapter; a specialist adapter governs domain technique only. Record the selected adapter in the handoff so another provider can substitute an equivalent capability without changing the behavior contract.

Present the evidence map, task DAG, and complete two-file handoff preview for every task as one implementation plan using `references/templates.md`. Ask for approval and stop. Do not self-approve. After approval, materialize the approved handoffs under `docs/cog2/<plan-slug>/tasks/` unless the repository has an established planning-artifact location.

## Phase 4: Red-Green-Refactor Execution

After approval, execute handoffs in dependency order. Treat each approved `.feature` plus `.md` pair as the complete task boundary. Before editing code, read both files and activate the recorded adapters when available. If an adapter is unavailable, preserve the handoff's discipline and contract using native reasoning and repository tools. Do not pull unrelated scenarios from the global plan into the task.

For every handoff:

1. Confirm the handoff has exactly one focused scenario and its dependencies are green. Resolve unavailable adapters to an equivalent available capability or `native instructions`; do not block solely because a named skill is absent.
2. Confirm every listed assertion uses the repository's real test framework and names a concrete expected value. Replace placeholders or broad assertions before proceeding.
3. **Red:** Add one minimal behavior test containing the handoff's listed assertions.
4. Run the narrow test and observe it fail for the expected missing behavior and expected assertion delta.
5. If it passes immediately, strengthen or correct the test before implementation.
6. If it errors for setup reasons, repair the setup until it fails for the intended reason.
7. **Green:** Add the smallest production change that makes the test pass.
8. Run the narrow test, then the relevant regression suite.
9. **Refactor:** Improve structure only while all tests remain green.
10. Record assertion-level red evidence, green evidence, regression results, files changed, and deviations in the handoff Markdown.

Never batch several unobserved red tests with a large implementation. Complete one coherent behavior cycle at a time. If repository constraints make strict TDD impossible, stop and explain the exact constraint rather than claiming compliance.

## Completion

Finish only when:

- every approved Gherkin scenario maps to a passing executable test
- every task has one approved `.feature`/`.md` handoff pair, names its required execution discipline, and records provider-resolvable adapters
- every handoff's exact assertions pass and its Red evidence shows at least one of those assertions failed for the intended behavioral reason
- all task verification commands pass
- relevant regression checks pass
- deviations and parked risks are reported
- no required work remains

Use the execution report in `references/templates.md`. Mark the goal complete through the selected adapter only after these conditions hold. Report provider usage metrics only when the provider returns them. If completion is genuinely blocked, preserve status `active` until the selected adapter's documented blocked threshold is met; do not mark incomplete work complete.

## Examples

**Feature plan:** The user says, "Add retry support to API calls." Ask what failures are retryable before suggesting a retry policy. Continue one branch at a time through attempt limits, idempotency, backoff, cancellation, and observability. After confirmation, inspect the HTTP abstraction and tests, write concrete retry Gherkin, then implement each scenario test-first.

**Bug plan:** The user says, "Fix duplicate notifications." Ask what event uniquely identifies a notification and what duplicate suppression must preserve. Confirm the invariant, trace event creation and persistence, specify examples for repeated and distinct events, then reproduce each failing case before changing production code.

## Resources

- Read `references/templates.md` when producing phase gates or the final report.
- Read `references/evaluations.md` when validating or revising this skill.
