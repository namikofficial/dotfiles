---
name: architecture-fitness
description: Enforce monorepo import-graph rules. Apps cannot import other apps; domain layer must not import framework code; shared packages must not depend on apps. Owns the import-graph checker script.
compatibility: opencode
---

## What I do

Make architectural boundaries executable instead of aspirational. If your architecture says "apps don't import each other", the CI should reject the violation, not the code reviewer.

Reference: ARCH-001, ARCH-002, ARCH-003 in `configs/engineering/invariants.yaml`.

## When to use me

Use this skill when:

- Setting up a new monorepo or adding a new package.
- Reviewing a refactor that crosses module boundaries.
- Auditing an existing codebase for hidden coupling.
- Adding a new framework dependency.

Do NOT use this skill for single-file scripts or for repos without a defined monorepo layout.

## Invariants enforced

| ID | Rule |
| --- | --- |
| ARCH-001 | In a feature-based monorepo, code under `apps/<a>/` may not import from `apps/<b>/` |
| ARCH-002 | Domain logic must not import Fastify, Express, TanStack Query, or any other framework |
| ARCH-003 | `shared/` packages must not depend on any `apps/<*>/` |

## Workflow

### 1. Detect the monorepo layout

The script supports two common layouts:

- npm/pnpm/yarn workspaces: detected by the presence of `package.json` with a `workspaces` field.
- Cargo workspaces: detected by the presence of `Cargo.toml` with `[workspace]`.
- Custom: declare the rules in `configs/engineering/architecture-fitness.yaml`.

### 2. Run the script

```sh
node configs/opencode/skills/architecture-fitness/scripts/check-import-graph.mjs \
  --workdir "$(pwd)"
```

The script emits JSON lines on stdout:

```json
{"rule":"arch/apps-cross-import","severity":"error","confidence":0.99,"file":"apps/web/src/foo.ts","line":12,"symbol":"(import)","evidence":"from \"apps/api/src/...\"","suggestedInvestigation":"move shared code to shared/ ... "}
```

### 3. Resolve

For each violation:
- If the import is genuinely needed in both places, move the shared code to `shared/<name>/`.
- If the import is accidental (an old path), fix the import statement.
- If the rule is too strict for this codebase, document an exception in `configs/engineering/architecture-fitness.yaml`.

### 4. Make it CI-enforced

Add the script to your CI:

```yaml
- name: architecture-fitness
  run: node configs/opencode/skills/architecture-fitness/scripts/check-import-graph.mjs --workdir $GITHUB_WORKSPACE
```

The script exits non-zero on `error`-severity findings.

## Custom rules

`configs/engineering/architecture-fitness.yaml` may declare additional rules:

```yaml
deny:
  - from: "apps/*/src/domain/**"
    import: "fastify"
    reason: "domain layer must not import framework"
  - from: "shared/**"
    import: "apps/*"
    reason: "shared packages must not depend on apps"
```

If the file is absent, the script falls back to the built-in defaults.

## Anti-patterns to refuse

- "It's just one file, the rule doesn't apply" — fix the rule or move the file.
- "We document this exception in the README" — make the exception explicit in the architecture-fitness config, not in prose.
- "Refactor it later" — the longer the violation lives, the harder it is to fix. Block at PR time.

## Output

When invoked on a task, return:

- Per-rule: count of violations and top-3 file:line locations
- Per-violation: which rule applies and the suggested fix
- Confirmation that no new violations were introduced by the change (for diffs)
