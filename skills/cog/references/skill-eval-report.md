# cog — skill evaluation report

Evaluation of the `cog` skill itself (not a pipeline it produces) against Anthropic's
official Agent Skills authoring + evaluation guidance.

## methodology (sourced)

Anthropic prescribes **eval-driven skill development**: discoverability first (the
name + description are the only signals Claude sees before triggering — measure
trigger rate, tune for fewer false positives AND false negatives), then output-quality
evals (realistic prompt + expected behavior + verifiable assertions), keep SKILL.md
lean with one-level-deep progressive disclosure, and validate structure against the
frontmatter rules. Sources at the bottom.

## conformance scorecard — official "Checklist for effective Skills"

### core quality
- [x] description specific + includes key terms
- [x] description states both what + when
- [x] **description ≤ 1024 chars — 917** (was 1090 → FIXED this pass)
- [x] SKILL.md body < 500 lines — 235
- [x] additional detail in separate files (prompts/, contracts/, references/)
- [x] no time-sensitive info
- [~] consistent terminology — metaphor synonyms (forge / annealing / pipeline) are
  intentional framing, not drift; acceptable but noted
- [~] examples concrete — the concrete worked example (clamp end-to-end) lives in
  references/evals.md, not the SKILL.md body; acceptable via progressive disclosure
- [x] file references one level deep — 0 nested md→md links
- [x] progressive disclosure used appropriately
- [x] workflows have clear steps (5 stages, specifier 3 phases, gate schedule)

### frontmatter validation (hard rules)
- [x] name lowercase/numbers/hyphens, ≤ 64 — `cog`
- [x] no reserved words ("anthropic"/"claude") in name or description
- [x] no XML tags in description
- [~] naming: doc *recommends* gerund form (`processing-x`); `cog` is a noun. Allowed
  ("noun phrases" are listed acceptable) and is the established brand — keep.

### code & scripts
- N/A — cog ships prompts + JSON-schema contracts, no executable scripts. See
  recommendation R1 (a schema validator would let the pipeline run the doc's
  "validator → fix → repeat" feedback loop deterministically).

### testing
- [x] ≥ 3 evaluations created — references/evals.md (activation, non-activation,
  refusal edge, pipeline gates, end-to-end smoke)
- [ ] tested with Haiku / Sonnet / Opus — NOT DONE (needs a run harness; out of scope
  for a static authoring session)
- [ ] tested with real usage — NOT DONE (same)

## discoverability / triggering assessment

The description is third-person, leads with what, ends with an explicit "Use when…"
clause, and carries strong trigger terms (spec-to-code, Gherkin, mutation testing,
decomposition pipeline, informal to formal). Post-fix it is within budget, so it will
not be rejected by the loader.

Risk: `cog` is a short common English word; on its own the *name* is a weak trigger
signal. Mitigation already in place — the description, not the name, carries the
triggers. Empirical trigger-rate measurement (run each eval query 3×, split 60/40
train/held-out, tune to cut false pos/neg) is the recommended next step but requires a
runner this session does not have.

## findings & fixes applied this pass

| # | sev | finding | status |
|---|-----|---------|--------|
| E1 | blocker | description 1090 chars > 1024 hard limit | FIXED → 917 |
| E2 | note | naming is noun not gerund | accepted (allowed; brand) |
| E3 | note | concrete example only in evals.md, not SKILL body | accepted (prog. disclosure) |

(These are in addition to the earlier internal-consistency pass: F1 gate-0b contract
gap, F2 CRAP formula, F3 missing forge metrics — all fixed; see git history.)

## recommendations (not yet applied — would improve, need your go-ahead)

- **R1 — add a deterministic validator script.** `scripts/validate.py` that checks a
  handoff/decomposition/gherkin/mutation-report JSON against its schema. The official
  guide favors scripts for deterministic ops and the validator→fix→repeat loop; it
  also makes `green_gate_integrity` machine-checkable instead of prompt-honor-system.
- **R2 — run the trigger-rate + multi-model evals.** Execute references/evals.md
  activation prompts against Haiku/Sonnet/Opus, 3× each, to get a real trigger rate and
  catch false negatives from the short name. NOTE: the Console Evaluation Tool does NOT
  do this — it grades prompt OUTPUT (1–5, version compare), not skill activation. Use it
  instead to grade/tune individual stage prompts (it is the manual meta-learner loop);
  use a code runner/CI for the deterministic gates. See eval-framework.md "tooling".

## verdict

**Conformant after the E1 fix.** Structurally strong: lean SKILL.md, clean one-level
progressive disclosure, valid frontmatter, evals present. The only remaining gaps are
empirical (multi-model + real-usage trigger measurement) and one optional hardening
(R1 validator). Grade: solid pass on authoring quality; testing dimension is
"artifacts complete, execution pending."

## independent check — writing-skills (TDD-for-docs) lens

A second pass using the local `writing-skills` skill (obra/superpowers lineage),
whose criteria are stricter and partly CONFLICT with the platform doc above.

- **W1 — description should be WHEN-to-use, not a workflow summary.** writing-skills
  (citing its own testing) holds that a description summarizing the process makes
  Claude follow the summary instead of reading the skill body. cog's description
  spelled out the full stage chain — the exact anti-pattern. Status: FIXED — rewrote
  to "Use when…" triggers only, no workflow chain (589 chars). Chose writing-skills
  over the platform "what+when" on the user's instruction to follow writing-skills.
- **W2 — Iron Law: no skill without a failing test first.** Status: CLOSED — ran
  RED/GREEN subagent pressure tests on the discipline prompts (see
  pressure-tests.md). RED baseline (no skill) → coder shipped code, skipped tests.
  GREEN (with cog) → coder TESTS-FIRST, architect refused to weaken the mutation gate,
  refactorer refused to delete assertions. All GREEN under combined pressure; no new
  loopholes → REFACTOR closed nothing. Rationalization table + red flags recorded.
- **W3 — minor:** desc 917 chars > their <500 soft target; name `cog` is a noun vs
  preferred verb/gerund (kept — brand); SKILL.md verbose vs <500-word target
  (acceptable via progressive disclosure).

### decisions raised by the independent check
- **D1 (description):** DONE — workflow chain removed; description is now "Use when…"
  triggers only (writing-skills CSO format). Trigger-rate measurement (R2) still
  pending (needs a runner).
- **D2 (pressure test):** DONE — RED/GREEN subagent tests run for coder, architect,
  refactorer. See pressure-tests.md. Remaining (next iteration): pressure scenarios
  for the hardener "no merging" and specifier "don't shortcut PHASE 1" invariants.

## sources

- Anthropic — Skill authoring best practices (platform.claude.com/docs, agent-skills/best-practices): checklist, 1024-char description limit, name rules, ≤500-line SKILL.md, one-level references, eval-driven development.
- Anthropic Engineering — Equipping agents for the real world with Agent Skills.
- Anthropic / claude.com — Improving skill-creator: test, measure, and refine Agent Skills (trigger-rate tuning, 60/40 train/held-out, run each query 3×).
- Anthropic Engineering — Demystifying evals for AI agents.
