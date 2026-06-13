---
name: cog2
description: Runs a Socratic spec-to-code workflow that relentlessly interviews the user to resolve a plan, deeply explores the target codebase, derives Gherkin specifications and dependency-ordered tasks, then implements each behavior with observed red-green-refactor TDD. Use when the user mentions cog2, asks to turn a plan into tested code, wants assumptions surfaced before implementation, or requests Socratic requirements discovery followed by repository-grounded Gherkin and TDD execution.
---

# Cog2

## Goal

Turn an informal plan into verified code without guessing. Move through four strict phases:

1. Socratic convergence
2. Codebase exploration
3. Gherkin and task decomposition
4. Red-green-refactor execution

Execute the workflow; do not merely describe it.

## Core Rules

- Ask one question per user turn during the interview.
- Lead with questions that expose assumptions, consequences, evidence, and edge cases. Do not answer the design question for the user when a question can help them derive it.
- Resolve one decision branch depth-first before opening another.
- Treat vague answers as unresolved. Ask for an example, invariant, threshold, failure policy, or explicit tradeoff.
- Never invent requirements. Record unresolved items as parked, with their implementation risk.
- Do not inspect or edit the repository until the user confirms the shared-understanding summary.
- Do not write production code until the user approves the repository-grounded Gherkin plan.
- Do not write production code without first running a test and observing the expected failure.
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

Avoid implementation details unless they are part of the public contract. Prune duplicate scenarios only when they exercise the same equivalence class and outcome; record why.

Decompose implementation into the smallest dependency-ordered tasks that can complete one red-green-refactor cycle. Each task must include:

- behavior/scenario owned
- dependencies
- files expected to change
- first failing test and expected failure reason
- minimal implementation target
- verification command
- explicit non-goals

Present the evidence map, Gherkin, task order, and parked risks as one implementation plan using `references/templates.md`. Ask for approval and stop. Do not self-approve.

## Phase 4: Red-Green-Refactor Execution

After approval, execute tasks in dependency order. For every behavior:

1. **Red:** Add one minimal behavior test derived from its Gherkin scenario.
2. Run the narrow test and observe it fail for the expected missing behavior.
3. If it passes immediately, strengthen or correct the test before implementation.
4. If it errors for setup reasons, repair the setup until it fails for the intended reason.
5. **Green:** Add the smallest production change that makes the test pass.
6. Run the narrow test, then the relevant regression suite.
7. **Refactor:** Improve structure only while all tests remain green.
8. Record the scenario, red evidence, implementation, and green evidence.

Never batch several unobserved red tests with a large implementation. Complete one coherent behavior cycle at a time. If repository constraints make strict TDD impossible, stop and explain the exact constraint rather than claiming compliance.

## Completion

Finish only when:

- every approved Gherkin scenario maps to a passing executable test
- all task verification commands pass
- relevant regression checks pass
- deviations and parked risks are reported
- no required work remains

Use the execution report in `references/templates.md`. If goal-tracking tools are available and a goal was explicitly requested, mark it complete only after these conditions hold.

## Examples

**Feature plan:** The user says, "Add retry support to API calls." Ask what failures are retryable before suggesting a retry policy. Continue one branch at a time through attempt limits, idempotency, backoff, cancellation, and observability. After confirmation, inspect the HTTP abstraction and tests, write concrete retry Gherkin, then implement each scenario test-first.

**Bug plan:** The user says, "Fix duplicate notifications." Ask what event uniquely identifies a notification and what duplicate suppression must preserve. Confirm the invariant, trace event creation and persistence, specify examples for repeated and distinct events, then reproduce each failing case before changing production code.

## Resources

- Read `references/templates.md` when producing phase gates or the final report.
- Read `references/evaluations.md` when validating or revising this skill.
