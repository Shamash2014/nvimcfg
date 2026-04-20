local M = {}

function M.question_rule()
  return [[
<QuestionRule>
When you need to ask the user a clarifying question, end your response with:

QUESTION: <your question>
<Options>
first plausible answer
second plausible answer
third plausible answer
</Options>

- Always include the <Options> block with 2–5 concrete options.
- If the answer is open-ended, offer 2–3 representative interpretations the user can pick or override.
- The user may select one option OR provide a free-text answer via the composer.
- Keep each option to a single short line.
</QuestionRule>
]]
end

function M.explore_tail()
  return [[
<Output>
/path/to/project/src/foo.js:24:8,3,Some notes here about some stuff, it can contain commas
/path/to/project/src/foo.js:71:12,7,more notes, everything is great!
/path/to/project/src/bar.js:13:2,1,more notes again, this time specfically about bar and why bar is so important
/path/to/project/src/baz.js:1:1,52,Notes about why baz is very important to the results
</Output>
<Rule>Text locations are in the format of: /path/to/file.ext:lnum:cnum,X,NOTES
lnum = starting line number 1 based
cnum = starting column number 1 based
X = how many lines should be highlighted
NOTES = A text description of why this highlight is important

See <Output> for example
</Rule>
<Rule>NOTES cannot have new lines</Rule>
<Rule>You must adhere to the output format</Rule>
<Rule>Double check output format before writing it to the file</Rule>
<Rule>Each location is separated by new lines</Rule>
<Rule>Each path is specified in absolute pathing</Rule>
<Rule>You can provide notes you think are relevant per location</Rule>
<Rule>You must provide output without any commentary, just text locations</Rule>
<Example>
You have found 3 locations in files foo.js, bar.js, and baz.js.
There are 2 locations in foo.js, 1 in bar.js and baz.js.
<Meaning>
This means that the search results found
foo.js at line 24, char 8 and the next 2 lines
foo.js at line 71, char 12 and the next 6 lines
bar.js at line 13, char 2
baz.js at line 1, char 1 and the next 51 lines
</Meaning>
</Example>
<TaskDescription>
you are given a prompt and you must search through this project and return code that matches the description provided.
</TaskDescription>

<Focus>
Beyond exact matches, also include:
- Missing work: TODO / FIXME / XXX / HACK / "not implemented" / empty or
  stub function bodies / placeholder literals / commented-out call sites
  touching the topic.
- Unfinished: partial implementations, fall-through branches, switch arms
  without a case for this topic, signatures whose bodies don't match,
  skipped or pending tests (`.skip`, `xdescribe`, `xit`, `pending`,
  `todo`).
- Co-change candidates: other callers of the same symbol, sibling
  implementations (interface/base/impl pairs), tests covering it, docs
  or schema entries that reference it, config keys, public re-exports.

For each such location, the NOTES field should state which bucket applies
and why — e.g., "TODO: handle quota", "stub: returns nil", "caller pair:
updates here should match foo.lua:42".

If nothing matches a bucket, skip it silently — do not invent locations.
</Focus>

<Interaction>
If the user's intent is ambiguous or you need a disambiguator before you can
answer, you may end a turn with a QUESTION (see QuestionRule below).

The user will answer on the next turn. Ask at most two questions across the
whole search, and only when truly necessary. When you have enough context,
output the final <Locations> block as described above.
</Interaction>
]] .. M.question_rule()
end

function M.routine_wrap(user_prompt)
  return user_prompt
end

function M.composer_sections_rule()
  return [[
<ComposerSectionsRule>
Before the `<Review>` block, emit these four blocks in order so the user's composer can pre-fill them:

<Summary>one-paragraph plain-English recap of what happened this turn</Summary>
<Review>path:line[:col]: note — locations worth re-reading (body may be empty, `title` attr optional; matches Review below if you keep one)</Review>
<Observation>non-location notes: surprising findings, risks, open questions, decisions that need sign-off</Observation>
<Tasks>checkbox bullets (`- [ ] …`) of follow-ups the user should pick up next — keep terse, one line each</Tasks>

- All four blocks are required. Use an empty body if a section has nothing to say — never omit a tag.
- Tags are case-sensitive: `Summary`, `Review`, `Observation`, `Tasks`.
</ComposerSectionsRule>
]]
end

function M.routine_tail()
  return [[
<ReviewRule>
You MUST end every turn with exactly one block:

<Review title="one-line summary of what this turn accomplished">
path:line[:col]: short note on what changed or why to look here
path:line: ...
</Review>

- The `title` attribute is required and must be a concise one-line summary (for pure-analysis turns, summarize what was concluded instead of what changed).
- One location per line. Use absolute or repo-relative paths.
- Include every file you touched and every location worth reviewing.
- If there are no locations to review, keep the body empty but still emit the block with its title.
- The block must be the last thing in your response, after any prose.
</ReviewRule>

<AskUserRule>
If you need the user to make a routing decision (pick an approach, resolve an ambiguity, choose a file/target, etc.) emit a single `<AskUser>` block *before* the Review block:

<AskUser>
The question text. Keep it to one or two lines.
<Options>
- option one
- option two
- option three
</Options>
</AskUser>

- Only emit `<AskUser>` when the next step genuinely depends on the user's choice. Do not use it for small clarifications you can answer yourself.
- `<Options>` is optional. When present, list 2–9 mutually exclusive options the user can pick numerically.
- The user's answer will be delivered as the next turn's prompt — continue from there.
- Do not emit more than one `<AskUser>` per turn.

**Dispatch prioritization.** When the routing decision is "which of these units of work should we do first", nest a `<Tasks>` block inside `<AskUser>` instead of `<Options>`:

<AskUser>
Found several distinct units of work. Which should I tackle first?
<Tasks>
## 01 — wire the ingestion parser for gzip
## 02 — expose /healthz and fold it into the smoke test
## 03 — document the on-call rotation for the new pipeline
</Tasks>
</AskUser>

- Each task is `## <id> — <one-line description>`. The id is short, unique, no spaces. Dependencies / subtasks / acceptance criteria are NOT required for this picker — keep entries to one heading line each.
- Entries are presented as numeric picks; the user's selection is sent back as the next prompt.
- Use `<Tasks>` form only when the user is really prioritizing discrete tasks. For yes/no or approach choices, stick with `<Options>`.
</AskUserRule>

]] .. M.composer_sections_rule()
end

function M.autorun_phase_tail(phase, ctx)
  ctx = ctx or {}
  if phase == "plan" then
    return [[
You are the **Planner** in a three-phase harness (Planner → Generator → Evaluator).

Expand the user's short prompt into an ambitious, cohesive product spec, then decompose it into sprints. Each sprint = one shippable feature.

Guidance:
- Be ambitious about scope. Prefer a product that feels complete and opinionated over a demo.
- Stay at product / high-level technical design. Do NOT dictate granular implementation (file names, function signatures, library choices beyond the stack) — the Generator figures that out.
- Weave AI features into the product where they add real value (summarization, retrieval, nudges, classification, auto-fill). Avoid AI-for-AI's-sake.
- If anything is genuinely ambiguous, ask via QuestionRule before emitting the plan.

Emit the decomposition as a `<Tasks>` block in markdown. Each task is one sprint:

<Tasks>
## 01 — short sprint description

### Deps
- 00

### Subtasks
- [ ] first sub-deliverable
- [ ] second sub-deliverable

### Acceptance
- required: observable outcome a reviewer can click-test
- optional: nice to have

## 02 — next sprint description

### Acceptance
- required: another observable outcome
</Tasks>

Rules:
- Each task starts with `## <id> — <short description>`. The id is unique, no spaces.
- Level-3 sections (omit empty):
  - `### Deps` — bullet list of earlier sprint ids this depends on.
  - `### Subtasks` — `- [ ] …` display-only breakdown.
  - `### Acceptance` — bullets `- required: …` / `- optional: …`. At least one required per sprint.
- End your response with `PLAN_COMPLETE` on its own line.

]] .. M.question_rule()
  elseif phase == "generate" then
    local task_id = ctx.current_task_id or ""
    local sprint_no = ctx.sprint_no or "?"
    local sprint_total = ctx.sprint_total or "?"
    local feedback = ctx.eval_feedback or ""
    local feedback_block = ""
    if feedback ~= "" then
      feedback_block = "\n\nEvaluator feedback from the previous attempt on this sprint — address every point:\n<Feedback>\n" .. feedback .. "\n</Feedback>\n"
    end
    local base = "You are the **Generator** (sprint " .. tostring(sprint_no) .. "/" .. tostring(sprint_total) .. "). Implement sprint `" .. task_id .. "` end-to-end. Work one feature at a time, self-review before handing off, and commit to git at sprint end with a conventional commit message. End the turn with one of:\n- `TASK_COMPLETE:" .. task_id .. "` when the sprint ships and you've self-evaluated\n- `TASK_BLOCKED:" .. task_id .. "` with a reason above (only when you genuinely cannot proceed)\n- QUESTION (see QuestionRule) if you need a product decision from the user" .. feedback_block
    local review_tail = "\n\nEmit the four composer blocks (Summary / Review / Observation / Tasks) just before a `<Review title=\"...\">` summary block for the sprint. The Summary should explain what ships; Observation should flag risks the Evaluator will want to poke at."
    return base .. review_tail .. "\n\n" .. M.composer_sections_rule() .. "\n" .. M.question_rule()
  elseif phase == "evaluate" then
    local task_id = ctx.current_task_id or ""
    local sprint_no = ctx.sprint_no or "?"
    local sprint_total = ctx.sprint_total or "?"
    local threshold = ctx.grade_threshold or 3
    return "You are the **Evaluator** (sprint " .. tostring(sprint_no) .. "/" .. tostring(sprint_total) .. "). Test sprint `" .. task_id .. "` like a real user.\n\n" ..
      "How to evaluate:\n" ..
      "- If a web UI is running, drive it via Playwright MCP (navigate, click, fill forms, assert state). Otherwise exercise CLIs, hit API endpoints with curl, inspect DB/state directly.\n" ..
      "- Walk the golden path end-to-end, then probe 1–2 likely edge cases.\n" ..
      "- Record every bug you find.\n\n" ..
      "Grade four dimensions 0–5: `product_depth`, `functionality`, `visual`, `code_quality`. Threshold: " .. tostring(threshold) .. ".\n\n" ..
      "Emit a `<Review title=\"eval: <task_id>\">` with bug locations (`path:line: note`). Then on separate lines:\n" ..
      "`product_depth=<n> functionality=<n> visual=<n> code_quality=<n>`\n" ..
      "Then ONE of:\n" ..
      "- `EVAL_PASS:" .. task_id .. "` — if all four dimensions ≥ " .. tostring(threshold) .. " and no critical bug.\n" ..
      "- `EVAL_FAIL:" .. task_id .. "` — otherwise, plus a `<Feedback>…</Feedback>` block with concrete, prioritized fixes for the Generator.\n\n" ..
      M.composer_sections_rule() .. "\n" .. M.question_rule()
  end
  return ""
end

return M
