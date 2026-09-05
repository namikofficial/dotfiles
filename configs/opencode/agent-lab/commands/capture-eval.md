# /capture-eval

After any successful real fix, the build agent runs `/capture-eval` to package the fix into a reusable golden task for `agent-lab`.

## When to invoke

Invoke immediately after the fix is verified and before declaring the task fully done. Not for trivial fixes (typos, one-line cosmetic changes).

## Inputs

- The owning product repo path (from `.agent-profile.yaml` `golden_root`, or the workdir if no profile).
- The fix's source repo + commit SHA before and after the change.
- The user-visible problem statement.
- The acceptance criteria (what "right" looks like).
- The diff (changed files).
- Any test that caught the bug or validates the fix.

## Output

```
<golden_root>/<product>/<task-slug>/
├── problem.md
├── repo_snapshot/             # NOT populated by /capture-eval; runner fetches via git checkout
├── expected-invariants.json   # what must remain true after the fix
├── hidden-tests/              # tests that exercise the bug's failure mode
├── expected-files.json        # files that should / should-not change
├── forbidden-changes.json     # protected files (auth, migrations, etc.)
└── meta.json                  # source commit, captured date, owning repo path
```

## Procedure

1. Read `.agent-profile.yaml` from the workdir (if present) to determine `golden_root` and `profile`.
2. Read `.ai/state.md` to identify the current task and owning repo.
3. Resolve the before/after git SHAs:
   ```sh
   git -C <repo> rev-parse HEAD~1  # before
   git -C <repo> rev-parse HEAD    # after
   ```
4. Compute `changedFiles = $(git -C <repo> diff --name-only <before>..<after>)`.
5. Generate a slug from the task title (lowercase, hyphens).
6. Create the golden directory.
7. Write `problem.md` from the user's original request (verbatim if available, summarized if not).
8. Write `meta.json`:
   ```json
   {
     "capturedAt": "<ISO-8601>",
     "product": "<profile>",
     "sourceRepo": "<absolute path>",
     "beforeCommit": "<sha>",
     "afterCommit": "<sha>",
     "capturedBy": "build-agent",
     "agentVersion": "<model-id>"
   }
   ```
9. Write `expected-files.json`:
   ```json
   { "expected": [...changedFiles], "forbidden": [...read from scenario context...] }
   ```
10. Write `expected-invariants.json` with the invariants the fix preserves (consult the relevant skill — e.g. `tenancy-invariants` for backend work, `nox-ui-engineering` for UI work).
11. Move any failing-then-passing test into `hidden-tests/` (so future runs can verify they catch the bug).
12. Run `agent-lab run --scenario datasets/golden/<product>/<task>/scenario.json --baseline` to record the baseline run.

## Verification

After capture, run `agent-lab run --scenario datasets/golden/<product>/<task>/scenario.json` and confirm the harness reproduces the fix's PASS state. If it does not, fix the golden case until it does — otherwise the case is not reusable.

## Cleanup

`repo_snapshot/` is NOT committed. Add it to `.gitignore` in the dotfiles repo under `configs/opencode/agent-lab/datasets/golden/**/repo_snapshot/`.

## Re-runnability

Every captured case must re-run cleanly on a fresh checkout of `afterCommit` and produce the same gates passing. If a case becomes flaky (infrastructure drift, model version change), retire it to `datasets/golden/_archive/<product>/<task>/` with a `retired.json` explaining why.
