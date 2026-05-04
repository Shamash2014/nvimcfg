---
name: agent-team
description: Three-agent architecture (Planner/Generator/Evaluator) for autonomous application building. GAN-inspired pattern from Anthropic's harness design research.
---

# Agent Team — Planner / Generator / Evaluator

Orchestrates a three-agent team for building complete applications autonomously. Based on the GAN-inspired pattern: separate generation from evaluation to eliminate self-evaluation blindspot.

**When to use:** Building a new application or significant feature from a short prompt (1-4 sentences).

## Phase 1 — Planner

Launch a **Plan agent** with the user's prompt. The Planner expands it into a full product spec.

### Planner Instructions

Give the Plan agent these directives:

- Take the user's 1-4 sentence prompt and expand it into a comprehensive product spec
- Be **ambitious about scope** — push beyond the obvious minimum viable product
- Focus on **product context and high-level technical design**, NOT granular implementation details
- Specify WHAT to build and WHY, not HOW to implement each piece
- Identify opportunities to weave AI-powered features into the product
- Define user stories, key screens/views, data model overview, and integration points
- Write the spec to `SPEC.md` in the project root

### Why No Implementation Details

Errors in a granular spec cascade into downstream implementation. Constrain agents on deliverables and let the Generator figure out the path during implementation.

### Planner Output

The Planner writes `SPEC.md` containing:
- Product vision and goals
- Feature list organized by priority
- User stories for each feature
- High-level technical architecture (stack, data model, key integrations)
- AI feature opportunities
- Success criteria

**Review checkpoint:** Read `SPEC.md` and confirm it matches user intent before proceeding.

## Phase 2 — Generator

Launch a **general-purpose agent** (or multiple parallel agents for independent features) to implement the spec.

### Generator Instructions

Give the Generator agent these directives:

- Read `SPEC.md` and implement the application feature-by-feature
- For each feature:
  1. State what you will build and how you will verify it works ("done" contract)
  2. Implement the feature
  3. Make an atomic git commit with a descriptive message
  4. Self-evaluate: does it work? Does it integrate with previous features?
- Work through ALL features in the spec — do not stop early or cut scope without explicit reason
- Prioritize working end-to-end functionality over polish
- Follow existing codebase patterns if building within an existing project
- Use established libraries and frameworks — do not reinvent

### Generator Output

- Working application with git history showing feature-by-feature progress
- Each feature committed atomically

## Phase 3 — Evaluator

Launch a **separate agent** to evaluate the Generator's work. The separation is critical — the same agent that built the code has a blindspot for its own flaws.

### When to Skip the Evaluator

Skip if the task is well within the model's baseline capability (simple CRUD, single-page apps, small utilities). The evaluator adds value when the task is at the **edge** of what the Generator handles reliably solo.

### Evaluator Instructions

Give the Evaluator agent these directives:

- Read `SPEC.md` to understand what was promised
- Review the implemented application against the spec
- Test the application like a real user — click through UI, test API endpoints, verify data persistence
- If browser testing is available (Playwright MCP), use it to interact with the running app
- Grade against these four criteria on a 1-10 scale:

**Grading Criteria:**

| Criterion | What to evaluate | Fail threshold |
|-----------|-----------------|----------------|
| **Product depth** | Does it have real features or just scaffolding? Are features complete with edge cases handled? | < 6 |
| **Functionality** | Do features actually work end-to-end? Can a user complete core workflows? | < 7 |
| **Visual design** | Is the UI cohesive and polished? Do colors, typography, and layout form a distinct identity? | < 5 |
| **Code quality** | Is the code clean, well-structured, and maintainable? Proper error handling at boundaries? | < 6 |

- For each criterion below threshold: provide specific, actionable feedback describing what is wrong and what "good" looks like
- Write the evaluation to `EVALUATION.md`

### Evaluator Output

`EVALUATION.md` containing:
- Score per criterion with justification
- PASS or FAIL verdict
- If FAIL: prioritized list of issues with concrete fix descriptions

## Phase 4 — Iteration (if Evaluator fails)

If the Evaluator returns FAIL:

1. Launch a new Generator agent with:
   - The original `SPEC.md`
   - The `EVALUATION.md` feedback
   - Instruction: "Fix ONLY the issues identified in EVALUATION.md. Do not refactor or change working features."
2. After fixes, run the Evaluator again
3. **Maximum 2 iteration rounds** — if still failing after 2 rounds, present the evaluation to the user for guidance

## Key Principles

1. **Separate generation from evaluation** — never let the builder be the sole judge of its own work
2. **Spec deliverables, not implementation** — tell agents WHAT, let them figure out HOW
3. **Atomic commits per feature** — clean git history enables targeted rollback
4. **Fail fast with thresholds** — concrete numbers prevent the evaluator from rubber-stamping
5. **Bounded iteration** — max 2 fix rounds prevents infinite loops
