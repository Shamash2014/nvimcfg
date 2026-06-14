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

## Goal Tracking

Prompt: `Use cog2 to add idempotent payment retries.`

Expected: Treat explicit Cog2 invocation as an explicit goal-tracking request. Use a native goal API when available, a persistent task API next, or emit a portable Goal Ledger before the first Socratic question. Preserve goal state across approval gates and mark it complete only after every handoff and verification condition passes.

## Atomic Handoff Shape

Prompt: `The plan needs success, timeout, and cancellation behavior. Produce the cog2 implementation plan.`

Expected: Produce three dependency-ordered handoff pairs. Each `.feature` preview contains exactly one focused scenario. Each matching `.md` preview requires test-first red-green-refactor, records a provider-resolvable TDD adapter and specialist adapter, and carries red, green, verification, dependencies, and non-goals.

## Assertion Specificity

Prompt: `Specify a task where an exhausted retry returns HTTP 503 after exactly three attempts.`

Expected: The Gherkin names status 503 and attempt count 3. The Markdown lists framework-native assertions equivalent to `expect(response.status).toBe(503)` and `expect(client.calls).toHaveLength(3)`, plus the exact Red delta. Reject `expect(response).toBeTruthy()`, a broad snapshot, or "assert retry fails correctly."

## Skill Routing

Prompt: `Use cog2 to optimize a slow React Native screen.` The available skills include `argent-react-native-optimization`, `argent-react-native-profiler`, and generic TDD.

Expected: Require test-first red-green-refactor. When installed, select `$tdd:test-driven-development` as the TDD adapter and `$argent-react-native-optimization` as the specialist adapter because its trigger directly matches the work. On a provider without those skills, record `native instructions` and the closest real native capability or `none`; preserve the same behavior and verification contract.

## Provider Portability

Prompt: `Run cog2 on a provider with repository tools but no goal API, no skill registry, and no usage metrics.`

Expected: Start with a portable Goal Ledger, execute the TDD discipline directly, use `native instructions` and `none` adapters, create the same two-file handoffs, and omit unavailable usage metrics. Do not stop or weaken the workflow because provider-specific integrations are absent.

Prompt: `Run cog2 on a provider that can converse but cannot access or execute the repository.`

Expected: Complete convergence and produce portable handoff previews, keep the goal active, and name repository access as the blocker. Do not claim Red, Green, implementation, or completion evidence.

## Validation Checklist

- The interview asks exactly one question per user turn.
- Questions expose reasoning instead of supplying design answers prematurely.
- Both human gates stop and wait for explicit approval.
- Explicit Cog2 invocation always enters goal mode through a native API, persistent task API, or portable Goal Ledger.
- Repository claims cite inspected files or commands.
- Every task is a two-file `.feature`/`.md` handoff with exactly one focused scenario.
- Every handoff requires test-first red-green-refactor and records provider-resolvable TDD and specialist adapters.
- Missing named skills or provider APIs trigger documented fallbacks rather than blocking or weakening the workflow.
- The portable handoff contract contains no mandatory provider-specific tool name, model name, or invocation syntax.
- Distinct success, boundary, and failure outcomes are separate handoffs.
- Every task lists exact framework-native assertions with concrete expected values and an expected Red delta.
- Broad truthiness and snapshot assertions are rejected when precise observations exist.
- Production edits occur only after observed red.
- Completion includes focused and regression evidence.
