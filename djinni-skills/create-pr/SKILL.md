---
name: create-pr
description: Prepare and open a GitHub pull request for the current branch using gh, driven by the commits on this branch
---

# Create PR

Open a pull request for the current branch. Follow these steps in order, verifying each before moving on.

## Preconditions

1. `git status` is clean — if there are uncommitted changes, surface them and stop. Ask the user whether to commit or stash before continuing.
2. Current branch is not `main` / `master` / `trunk`. If it is, stop and ask the user to create a feature branch first.
3. `gh auth status` succeeds. If not, report it and stop.

## Gather context

Run in parallel:
- `git rev-parse --abbrev-ref HEAD` — current branch
- `git config --get remote.origin.url` — derive `<owner>/<repo>`
- `git log --oneline origin/main..HEAD` (fall back to `master` / the detected default branch if `main` is absent)
- `git diff --stat origin/main..HEAD`
- `gh pr list --head <branch> --json number,url` — skip creation if one already exists; instead print its URL.

## Push

If the branch is not tracking a remote or is behind, `git push -u origin <branch>`. Never `--force` without the user's explicit approval.

## Title

- Pull from the first commit subject on the branch. Strip any trailing issue number.
- Keep under 70 chars. If you have to shorten, prefer cutting the scope qualifier over the verb.

## Body

Use a HEREDOC for `gh pr create --body`. Body template:

```
## Summary
- <one bullet per meaningful commit, past tense, imperative verb dropped>

## Changes
- <file-area>: <short note>  (group commits by area, not by commit)

## Test plan
- [ ] <specific check the reviewer can run>
- [ ] <another check>

## Notes
<anything the reviewer needs to know: follow-ups, known gaps, risky assumptions>
```

Rules:
- Do not invent checks the code can't actually verify. If there are no tests, say so.
- Do not include the co-author trailer in the PR body (commits already carry it).

## Create

```
gh pr create \
  --title "<title>" \
  --body "$(cat <<'EOF'
<body>
EOF
)" \
  --base <default-branch>
```

If the user asked for a draft or a specific base, honor that instead.

## Report

Print the PR URL returned by `gh`. Do not run any follow-up browser command unless the user asked.
