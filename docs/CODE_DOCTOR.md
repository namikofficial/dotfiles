# Code Doctor

Code Doctor is a reusable local JavaScript/TypeScript scanner in
`tools/code-doctor`. It uses the TypeScript compiler API and checker (never
grep-only symbol detection) and writes `.code-doctor/report.json` plus
`.code-doctor/AGENT_FIXES.md` in the project being scanned. It does not execute
project code or send repository data anywhere.

## Installation and use

Run `./setup/bootstrap.sh` once, or link `tools/code-doctor/code-doctor` to
`$HOME/.local/bin/code-doctor`. Then run `code-doctor` from any repository.

`code-doctor --full` additionally checks for locally installed `eslint` and
`knip` (it never installs them). `--changed` limits findings to Git changed
files, including staged changes. `--project path/to/tsconfig.json` selects a
project explicitly. `--output path` directs `report.json` and
`AGENT_FIXES.md` to a chosen directory (`--out` remains an alias).
`--json` emits the stable report as one JSON document;
`--quiet` suppresses terminal details. `--fail-on error|warning|deprecated`
sets CI-friendly exit status; the default always exits zero after writing the
report. `--help` and `--version` are supported.

The scanner discovers tsconfig files, project references, and JS-only projects,
while excluding common generated/vendor directories. It resolves TypeScript
from the project first and falls back to the local runtime installation.

Checks include deprecated symbols/signatures (including aliases and dependency
`.d.ts` declarations), compiler diagnostics, unsafe suppressions,
undocumented `@ts-expect-error`, explicit `any`, and non-null assertions.
Promise and Knip/ESLint checks are reported as optional integrations when those
tools are installed in the project. Limitations: v1 does not perform full
dependency graph invalidation for `--changed`, and optional tool output is not
reimplemented by Code Doctor.

## Agent workflow

Run `code-doctor --full`, have the coding agent read `.code-doctor/AGENT_FIXES.md`,
fix root causes without adding suppressions, run project tests, then rerun the
doctor. The report's `ruleId` and finding fields are stable enough for a future
baseline/SARIF mode.
