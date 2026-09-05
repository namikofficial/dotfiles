# agent-lab

The evaluation infrastructure for the OpenCode setup. Treats every skill, model, prompt, agent, context strategy, and tool as an experimental variable, and benchmarks them all against reproducible engineering tasks.

## Core principle

The unit of improvement is not "a skill". The unit of improvement is **a reproducible engineering task with observable success criteria**. Skills, models, prompts, agents, context strategies, advisor calls, MCPs, and plugins are all experimental variables tested against those tasks.

## Layout

```
agent-lab/
├── scenarios/               # synthetic scenarios (synthetic-test territory)
│   ├── ui/
│   ├── backend/
│   ├── debugging/
│   └── architecture/
├── datasets/
│   └── golden/              # real-bug tasks captured from actual work (/capture-eval)
├── fixtures/                # shared test fixtures
├── runners/
│   └── opencode.ts          # executes scenarios through OpenCode headless
├── graders/
│   ├── deterministic/       # ast-grep, LSP, git diff, test runner
│   ├── browser/             # browser MCP for per-state screenshots
│   ├── visual/              # vision / vision-expert agents
│   ├── security/            # tenancy-invariants scripts
│   └── llm/                 # LLM judge for qualitative dimensions
├── experiments/
│   ├── model/               # M3 vs M2.7 vs Luna
│   ├── skill/               # with-skill vs without-skill
│   ├── prompt/              # prompt variants
│   ├── agent/               # agent roster variants
│   ├── context/             # context-contract quality
│   └── tool/                # LSP on/off, browser on/off
└── results/
    ├── baseline/            # committed golden runs (ground truth)
    └── runs/                # every new run, timestamped
```

## Hard gates + dimensions (not single averaged score)

Every grader emits findings using the same structured shape:

```json
{
  "rule": "tenant/client-supplied-scope",
  "severity": "error",
  "confidence": 0.97,
  "file": "src/foo.ts",
  "line": 82,
  "symbol": "createPart",
  "evidence": "companyId: req.body.company_id",
  "suggestedInvestigation": "derive company from authenticated workspace context"
}
```

For task-level scoring, results are reported as:

```
HARD GATES (all must PASS)
  Correctness
  Required states covered
  No console errors
  Keyboard path complete
  A11y critical (focus, labels, error association)

DIMENSIONS (0–10 each)
  Visual hierarchy
  Typography
  Density
  Spacing rhythm
  Distinctiveness
  Polish
```

A 100 in dimensions cannot compensate for a failing hard gate. Same idea for backend tasks: tests, contracts, security, observability each get hard gates.

## Provenance tags

Every grader finding carries a provenance tag:

- `OBSERVED` — direct evidence, recorded with file:line or test output
- `INFERRED` — reasoning from OBSERVED facts
- `ASSUMED` — taken as true without evidence; must be flagged
- `UNVERIFIED` — claim made without evidence; must be flagged

These tags show up in verification reports and gate reporting.

## Severity model

Grader findings use three severity levels:

- `error` → hard gate failure; task fails
- `warning` → surfaced but does not by itself fail the task
- `advisory` → logged; included in reports only

## Usage

```
# Run all scenarios (synthetic + golden)
agent-lab run

# Run a specific scenario
agent-lab run --scenario scenarios/ui/shipment-table-redesign.json

# Run the golden suite only
agent-lab run --suite golden

# Run a skill experiment (with-skill vs without-skill)
agent-lab run --experiment experiments/skill/nox-ui-engineering.json

# Baseline run for the current state
agent-lab run --baseline
```

## /capture-eval

After any successful real fix, the build agent runs `/capture-eval` to package the fix into `datasets/golden/<product>/<task>/`. See `commands/capture-eval.md`.

## Eval contract for new skills

Every custom skill ships with:

- `evals/cases.json` — ≥ 3 cases with hard gates + dimension scores
- `evals/rubric.md` — what each dimension means for this skill

It is not considered shipped until `agent-lab run --skill <name>` shows improvement ≥ N (per-skill) over `experiments/skill/baseline.json`.

## Invariants

The invariants this layer enforces:

- Every grader output uses the same structured diagnostic shape.
- Every scenario JSON validates against `fixtures/scenario.schema.json` before running.
- Every run produces a timestamped result in `results/runs/` and never silently overwrites.
- Baseline runs are committed; experimental runs are gitignored.
