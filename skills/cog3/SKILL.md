---
name: cog3
description: "Provider-agnostic Socratic spec-to-code workflow that fuses Cog2's discipline with the autoresearch (property-as-metric) loop. It resolves the plan by questioning, explores the codebase, decomposes work into atomic two-file handoffs — each carrying a property-based acceptance metric plus seed examples — then drives every handoff to green with an autonomous generate-test-score-mutate loop that freezes each property counterexample into a permanent example test, stabilizes across seeds, and refactors; finally it simplifies touched code and reviews the touched architecture. Enforces goal mode and, for bugs, the Debug Mantra. Use when the user mentions cog3, or wants a plan or bug turned into property-tested code with assumptions surfaced first, atomic handoffs, autonomous test-driven implementation, and a final architecture review."
---

# Cog3

Cog3 = **Cog2's Socratic decomposition front-end + the autoresearch loop as the per-handoff execution engine.** Cog2 decides *what* to build (questioned, decomposed into atomic behaviors, gated by humans) and verifies each behavior with example-based TDD. Cog3 keeps all of that but adds the **property layer**: each atomic handoff defines universally-quantified properties as its acceptance metric, and is driven to correct *autonomously* by a generate-test-score-mutate loop where the Gherkin scenario seeds the example suite and every property counterexample is frozen into a permanent regression. Cog2 = scope + human gates; the loop = drive each piece to provably-correct.

Move through five strict phases. **Execute the workflow; do not merely describe it.**

1. Socratic convergence
2. Codebase exploration
3. Gherkin + atomic decomposition **with a property metric per handoff**
4. **Autoresearch execution** (property-metric red-green-refactor loop per handoff)
5. Simplification and architecture review

For any bug, regression, failure, exception, flaky behavior, or diagnostic request, apply the **Debug Mantra Protocol** below as part of Cog3 — mandatory even if the standalone `debug-mantra` skill is unavailable.

## Goal mode

Invoking Cog3 is an explicit request to enter goal mode. Before Phase 1, initialize goal tracking with the first available adapter:
1. **Native goal API** — create a goal with the user's outcome. No token budget unless the user supplied one.
2. **Persistent task/plan API** — one top-level tracked item, kept active.
3. **Portable fallback** — emit a **Goal Ledger** (`references/templates.md`): objective, status `active`, current phase, completed/pending handoffs, blockers. Repeat at every phase gate and in the final report. After repo editing is approved, persist at `docs/cog3/<plan-slug>/goal.md`.

Keep the goal active through both human gates and all handoffs. Mark complete only after every completion condition is verified. Treat provider features as **adapters, not workflow semantics**: discover capabilities, map them to the required operation, fall back to conversational/file-based when absent. If a provider cannot read/write/execute the repo, finish the interview and handoff plan, keep the goal active, and report the missing execution capability as the blocker.

## Core Rules

- Ask **one question per user turn** during the interview. Lead with questions that expose assumptions, consequences, evidence, and edge cases; do not answer the design question for the user when a question can help them derive it.
- Resolve one decision branch depth-first before opening another. Treat vague answers as unresolved — ask for an example, invariant, threshold, failure policy, or explicit tradeoff. Never invent requirements; record unresolved items as parked, with their risk.
- **Gates:** do not inspect or edit the repo until the user confirms the shared-understanding summary; do not write production code until the user approves the Gherkin + handoff plan; do not write production code without first observing a real test failure (Red).
- Represent every implementation task as exactly **two handoff files**: one `.feature` (one focused scenario) and one `.md` (its execution contract) — **plus the handoff's property metric and seed examples** recorded in the `.md` (see Phase 3 and `references/templates.md`).
- Decompose recursively until every handoff delivers **one independently observable behavioral delta**, can complete one short loop, and has no internal step that could produce useful verified progress alone. Treat multiple code paths, acceptance outcomes, state transitions, side effects, error policies, or migration steps as presumptive split points. Reject handoffs joined by `and`/`then`/`plus` unless inseparable. Prefer more small dependency-ordered handoffs; never create bookkeeping-only tasks.
- Require each handoff to state its **exact executable assertions** (subject, framework-native matcher, concrete expected value, Red failure/diff) **and** its **properties** (universal invariants, with an archetype and generator) and **seed examples**. Reject vague assertions ("works", "is valid", truthiness) and vague properties (anything that merely restates the implementation or cannot fail).
- Each handoff embeds `Required execution discipline: autoresearch loop (property-metric red-green-refactor)`. Name a TDD/specialist adapter if installed; otherwise execute the discipline directly from `references/autoresearch-loop.md`. Never make completion depend on an optional provider integration.
- Preserve existing repository patterns and unrelated user changes. Modify only the handoff's target surface and its tests.
- After all handoffs are green, **simplify only code changed by this Cog3 run**, preserving exact behavior, then rerun focused + regression verification. Finish with a **bounded architecture review** of the touched area; report deepening opportunities, do not implement unapproved architectural expansion.

## Debug Mantra Protocol

Apply only when the outcome includes debugging/fixing faulty behavior. As the first user-visible content of the first debugging response, recite verbatim once:

> **Mantra:**
> 1. **First is reproducibility.** Can the issue be reproduced reliably?
> 2. **Know the fail path.** Debugger first; then source trace + knob enumeration; then in-code instrumentation.
> 3. **Question your hypothesis.** What would disprove it?
> 4. **Every run is a breadcrumb.** Cross-reference all of them.

If told to skip the mantra, skip only the recital and still apply the protocol. Before proposing/implementing a fix:
1. **Reproduce** — a fast deterministic pass/fail signal captured as a failing test/runnable artifact. If flaky, raise the reproduction rate first. No reproduction ⇒ stop and report missing evidence. (This reproduction becomes the loop's first seed example.)
2. **Trace the fail path** — debugger preferred; else source trace + enumerate every config/input/branch/timing/concurrency/build knob; tagged in-code instrumentation only after those are exhausted.
3. **Falsify** — keep 3–5 ranked hypotheses; for the leader state the simplest proof and cleanest disproof, run the disproof first.
4. **Cross-reference** — an experiment ledger of each run: what changed, what happened, what it ruled in/out. Reject any hypothesis contradicted by an earlier breadcrumb.

No fix before reproduction + fail-path evidence. No accepted root cause until its hypothesis survives falsification and explains every ledger entry. Remove temporary instrumentation before completion.

## Phase 1: Socratic Convergence

Start from the user's informal plan (ask if none). Silently build a decision tree covering: desired outcome and observable success; users/actors/entry points; scope and non-goals; inputs/outputs/state/invariants; happy path/edges/failure behavior; compatibility/migration/rollout/rollback; security/privacy/performance/operational constraints when relevant; verification and acceptance criteria.

Choose the highest-risk unresolved branch and ask **one** concise question (assumption? distinguishing observable? boundary/failure? what must stay unchanged? why over the strongest alternative? what would falsify it?). After each answer: restate the resolved decision, note any dependency unlocked, ask the next single question, and periodically report resolved/unresolved/parked counts.

When all material branches are resolved or parked, present the **shared-understanding summary** (`references/templates.md`). Ask the user to confirm or correct. **Stop. Do not enter Phase 2 without explicit confirmation.**

## Phase 2: Explore the Codebase

After confirmation, inspect before designing:
1. Read repo guidance; determine language, framework, build, **test command, per-test reporter (JSON/JUnit/TAP), lint, format**.
2. Identify the **property-based test framework** and **how to pin its seed** (Hypothesis `--hypothesis-seed`/`.hypothesis/`, fast-check `{seed}`, proptest `proptest-regressions/`, rapid `-rapid.seed`, etc.); if none is installed, adding it is a setup step.
3. Map entry points, modules, callers/callees, data flow, state transitions, side effects, public contracts. Read relevant files end-to-end incl. neighboring tests/fixtures. Search analogous implementations and local patterns. Inspect history when intent is unclear. Check worktree status and preserve unrelated changes. Run the narrowest useful baseline tests when practical.

For debugging, exploration also produces the runnable reproduction, fail-path trace, knob inventory, ranked hypotheses, falsification results, and ledger (Debug Mantra). Produce a concise **evidence map** (`references/templates.md`). If exploration invalidates a confirmed decision, return to Phase 1 for that branch only, ask one Socratic question, reconfirm the amended summary.

## Phase 3: Gherkin + Atomic Decomposition (with property metric)

Translate confirmed intent + repo evidence into example-based requirements. Write Gherkin where each scenario has one distinct behavior, concrete preconditions, a triggering action, observable outcomes, and boundary/failure examples where behavior differs. Make every `Then` concrete enough to become exact assertions (name the value, transition, effect, error type/message, count, ordering, or absence) — no `Then it works`.

Decompose into the smallest dependency-ordered tasks that can complete one loop. For each task, create the two-file handoff from `references/templates.md`. **Each handoff additionally specifies:**
- **PROPERTIES** — 1–4 universally-quantified invariants that are the handoff's acceptance metric (archetype + generator). For specialized domains take the right *kind* of property from the domain guidance — UI/frontend → `references/ui-mode.md`; data/ML, external I/O & APIs, concurrency, performance, generative/LLM, numerical → `references/domains.md`. A property must be able to fail.
- **SEED EXAMPLES** — the `.feature` scenario (E1) plus known edge/boundary cases and any bug reproduction.

Apply the recursive split test (assertions separable? branch/outcome/transition/effect/migration/failure-policy independently verifiable? touches unrelated ownership? Red contains >1 delta? intermediate green useful? conjunctions in the title?). Add an **Atomicity Proof** per handoff naming the single behavioral delta. After drafting the DAG, do a second decomposition pass from fresh context and split any remaining broad node.

Choose adapters by inspecting the provider's installed skills/tools (narrowest matching skill → native capability → `none`); record them in the handoff. Present the evidence map, task DAG, and complete two-file-plus-property handoff preview as **one implementation plan**. **Ask for approval and stop. Do not self-approve.** After approval, materialize handoffs under `docs/cog3/<plan-slug>/tasks/`.

## Phase 4: Autoresearch Execution

Execute handoffs in dependency order. Each approved `.feature`+`.md` pair is the complete task boundary. Before editing, read both files and activate recorded adapters (or preserve the discipline natively). **Do not** pull unrelated scenarios into the task.

For every handoff, run the **per-handoff autoresearch loop** in `references/autoresearch-loop.md`:
1. Confirm exactly one focused scenario and that dependencies are green; resolve unavailable adapters to an equivalent capability or native instructions.
2. **Recheck the Atomicity Proof against repository reality.** If implementation reveals another independently verifiable behavioral delta, **stop, split the approved handoff, and obtain approval for the changed plan before production edits.**
3. Confirm assertions and properties use the repo's real framework with concrete expected values and a real generator. For debugging handoffs, confirm reproduction is reliable, fail path traced, hypothesis survived disproof, breadcrumbs consistent.
4. **Run the loop:** write property tests + seed examples (Gherkin scenario among them) → observe Red → drive to green with the generate-test-score-mutate cycle (mutate-from-best, score on a fixed suite, freeze each counterexample into a new example test, keep/discard on the per-test vector) → stabilize across 3 seeds → bounded refactor-green. The loop is autonomous within its `max_cycles` budget; it does not ask permission per cycle but checkpoints every 10.
5. Record into the handoff `.md`: Red evidence, property + example pass vectors, counterexamples frozen, seeds, files changed, deviations (and, for debugging, final reproduction, root-cause evidence, falsification, full ledger). Advance the goal ledger.

Never batch several unobserved Red tests with a large implementation — one handoff's loop at a time. If repo constraints make the discipline impossible, stop and explain the exact constraint rather than claiming compliance.

## Phase 5: Simplification and Architecture Review

Enter only after every handoff is green and stable and its regression checks pass. The loop already refactored *within* each handoff; this phase is the **cross-handoff** pass over all Cog3-touched code.

**Simplify touched code** — activate `code-simplifier` if installed, else apply directly. Limit to production+test code modified during this run. Preserve all behavior, outputs, contracts, and passing assertions/properties. Reduce needless nesting, duplication, indirection, comments, abstractions only when clarity improves; prefer explicit control flow; keep useful abstractions. Rerun focused tests for every changed handoff **and the property suites** plus relevant regression after simplifying; revert anything that changes behavior.

**Review touched architecture** — activate `beautify` if installed, else apply a bounded review. Read `CONTEXT.md` and relevant `docs/adr/` when present. Inspect only modules touched by this run and their immediate callers. Use the vocabulary `module/interface/implementation/depth/seam/adapter/leverage/locality`; apply the deletion test to suspected shallow modules; treat the interface as the test surface; don't recommend a seam backed by one adapter unless future variation is an approved requirement. Record each real deepening opportunity (files/modules, interface or locality problem, proposed deepening, benefits, ADR conflicts) as numbered follow-ups. Do not implement unapproved architectural expansion. Architecture findings don't block completion unless they reveal an unmet acceptance criterion, invariant, or regression guarantee.

## Completion

Finish only when:
- every approved Gherkin scenario maps to a passing executable test, and **every handoff's properties are green and stable across 3 seeds**;
- every task has one approved `.feature`/`.md` handoff with properties + seed examples, names its execution discipline, and records provider-resolvable adapters;
- every handoff has a credible Atomicity Proof and survived both the planning split test and the pre-execution split check;
- every handoff's exact assertions pass, and its Red evidence shows at least one assertion/property failed for the intended reason;
- all task verification commands and relevant regression checks pass;
- counterexamples frozen during the loop are recorded and remain green;
- deviations, budget-exhausted handoffs, and parked risks are reported;
- debugging tasks record reliable reproduction, traced fail path, falsified-and-surviving root cause, complete ledger, and removed instrumentation;
- the final simplification pass covers only Cog3-touched code, preserves behavior, and passes focused + property + regression verification;
- the touched architecture is reviewed; findings reported without unapproved scope expansion;
- no required work remains.

Use the execution report in `references/templates.md`. Mark the goal complete through the selected adapter only after these conditions hold. Report provider usage metrics only when the provider returns them. If genuinely blocked, keep status `active` until the adapter's documented blocked threshold; never mark incomplete work complete.

## Resources

- `references/autoresearch-loop.md` — the per-handoff property-metric loop (Phase 4 engine).
- `references/templates.md` — goal ledger, phase-gate summaries, the property-carrying handoff, and the execution report.
- `references/ui-mode.md` — frontend domain adjustments (behavioral/a11y/responsive properties + visual-regression goldens).
- `references/domains.md` — property kinds for data/ML, external I/O, concurrency, performance, generative, and numerical work.
