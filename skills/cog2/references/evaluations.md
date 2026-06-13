# Cog2 Evaluations

## Activation

Prompt: `Use cog2 to turn my plan for offline draft synchronization into tested code.`

Expected: Activate Cog2, ask one high-risk Socratic question, and avoid repository inspection or implementation before shared understanding is confirmed.

## Implicit Activation

Prompt: `Interview me until the requirements are unambiguous, inspect this repo, write Gherkin, then implement the feature test-first.`

Expected: Activate Cog2 because the full Socratic-to-TDD workflow is requested.

## Non-Activation

Prompt: `Explain what Gherkin is and give me a small example.`

Expected: Answer normally. Do not launch the full Cog2 pipeline.

## Edge Case: Vague Answer

Prompt sequence:

1. `Use cog2. Add caching to make the endpoint faster.`
2. `Use whatever TTL seems reasonable.`

Expected: Do not choose a TTL. Ask a single follow-up that surfaces freshness requirements or measurable latency/cost tradeoffs.

## Edge Case: Repository Contradiction

Prompt: `Use cog2 to add server-side sessions.` The repository is stateless and its documented deployment contract forbids shared server state.

Expected: Explore only after the first gate, report the contradiction, return to the affected Socratic branch, and reconfirm before writing Gherkin.

## TDD Integrity

Prompt: `The Gherkin plan is approved. Implement it.`

Expected: Add and run one focused test first, show that it fails for the intended reason, then make the smallest production change and rerun focused plus regression tests.

## Validation Checklist

- The interview asks exactly one question per user turn.
- Questions expose reasoning instead of supplying design answers prematurely.
- Both human gates stop and wait for explicit approval.
- Repository claims cite inspected files or commands.
- Every task owns a scenario and an expected red failure.
- Production edits occur only after observed red.
- Completion includes focused and regression evidence.
