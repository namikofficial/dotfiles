# Agent Harness Audit

Date: 2026-09-22

## Executive result

The dominant cost was not a single bad prompt. It was context amplification:
long tool loops repeatedly carried accumulated instructions, reads, outputs,
polls, failures, and compaction state into later model calls. The corrective
architecture is therefore smaller persistent context, fewer selectable roles
and skills, bounded output, depth-one delegation, and explicit proportional
validation. Strong correctness gates remain for database, authorization,
device, and release work.

## Measured baseline

Codex rollout analysis streamed 841 JSONL files (3.32 GB) without emitting
transcripts. Only 213 sessions contained token telemetry, so token statistics
below use that subset.

| Measure | Result |
|---|---:|
| Codex sessions | 841 |
| Sessions with token telemetry | 213 |
| Median / p90 cumulative telemetry tokens | 2.66M / 38.20M |
| Maximum cumulative telemetry tokens | 606.09M |
| Model-authored tool / nested shell calls | 93,738 / 56,820 |
| Median / p90 tool calls per session | 31 / 235 |
| Detected failed commands | 3,641 |
| Tool outputs at least 20 KB | 6,491 |
| Compactions / sessions with compaction | 553 / 288 |
| Exact repeated commands | 5,128 |
| Subagent spawns / sessions spawning | 435 / 67 |
| Subagent coordination calls | 2,687 |

Read/search/validation classification is regex-based. The analyzer estimated
29,567 read-like commands, 18,226 searches, and many repeated path references;
these are directional, not precise file-read telemetry.

OpenCode's own lifetime stats reported 926 sessions, 798 child sessions,
97,831 model steps, and 129,239 tool calls. The last seven days alone reported
105 sessions, 182 children, 24,617 steps, and 29,865 tool calls, including 168
subagent calls with 23 failures. Cache reads dominated recorded input (2.72B
cached versus 75.6M uncached input tokens). CodeGraph had both a healthy tool
name (45/45 recent successes) and an obsolete/malformed form (102/102 failures).
Lifetime Maestro results were 9 successes and 36 failures.

The worst Codex session was a NoxOrigin physical-device loop: 4,312 tools,
2,533 shell calls, 1,165 process polls, 627 patches, 142 detected failures, 185
large outputs, and 24 compactions. A small successful dotfiles comparison used
12 tools, 11 shell calls, one patch, one scoped validation, no failures, and no
compaction.

## Highest-cost failure modes

| Rank | Problem | Evidence | Correctness impact | Root class | Correction |
|---:|---|---|---|---|---|
| 1 | Tool-loop context amplification | 2.66M median telemetry tokens; 606M max | Compaction and state loss late in work | Harness/platform | Batch reads, bound outputs, stop/restart long trajectories |
| 2 | Long polling/device loops | Worst session had 1,165 polls | False progress and unstable terminal state | Harness/model/runtime | Poll only when state can change; bounded device verifier |
| 3 | Unbounded tool output | 6,491 outputs >=20 KB | Important evidence buried; earlier compaction | Config/harness | 32 KB / 500-line OpenCode cap; 6,000-token Codex history cap |
| 4 | Overlong sessions after failures | 3,641 detected failures; max 239 | Repeated bad hypothesis and superficial recovery | Model/prompt | Inspect failure, change hypothesis, do not blind retry |
| 5 | Validation churn | Some sessions ran tens to hundreds of validation-like commands | Slow work; noisy evidence can hide real failure | Prompt/repo complexity | Risk matrix; no rerun after a pass without relevant edits |
| 6 | Repeated inspection | 5,128 exact repeated commands plus repeated read-path estimates | Stale assumptions and context growth | Model/prompt | Do not reread without changed state or new evidence |
| 7 | Delegation sprawl | 46 Codex spawns in one session; OpenCode 182 children/105 sessions in 7 days | Duplicated work and integration gaps | Config/prompt | Depth one; one independent bounded slice by default |
| 8 | Huge selectable OpenCode role surface | 15 configured roles and overlapping responsibilities | Tool/role confusion for weaker models | Config | Seven practical model-selecting roles; retain the user-authored skill catalog |
| 9 | MCP/tool naming drift | Recent obsolete CodeGraph form failed 102/102 | Exploration silently fails or loops | Platform/config | Keep canonical CodeGraph route and resolved-config checks |
| 10 | Wide persistent project instructions | NoxOrigin component chain was 14.8 KB | Irrelevant UI/runtime rules tax backend tasks | Prompt architecture | Root router plus scoped ownership deltas |
| 11 | Mandatory meta-work | `/auto`, `/handoff`, classification and state-file habits | Plans/docs replace implementation | Prompt/config | Remove routing commands; checkpoints only for long work |
| 12 | Credentials in prompt context | Local login fixture was in API `AGENTS.md` | Credential propagation into every API session | Documentation/security | Removed value; use guarded runtime fixture flow |

## Research summary

| Finding | Evidence | Applicability | Action | Confidence |
|---|---|---|---|---|
| Codex loads global-to-leaf instructions and caps their combined bytes | [OpenAI AGENTS.md documentation](https://learn.chatgpt.com/docs/agent-configuration/agents-md) | Direct | Keep root guidance as a router; cap at 16 KiB | High |
| Codex supports per-profile config, tool-output limits, MCP allowlists, and bounded subagent defaults | [OpenAI configuration reference](https://learn.chatgpt.com/docs/config-file/config-reference) | Direct to 0.155.1 | Add output/doc caps and opt-in capability profiles | High |
| OpenCode V2 lists permitted skills and uses ordered permissions | [OpenCode skills](https://opencode.ai/v2/docs/skills), [OpenCode agents](https://opencode.ai/v2/docs/agents) | Direct to resolved 2.0.11 behavior | Keep all authored skills available to build/plan while bounding worker depth | High |
| Long tool histories amplify input and compaction pressure | [Codex issue #44305](https://github.com/openai/codex/issues/44305), [OpenCode issue #8089](https://github.com/anomalyco/opencode/issues/8089) | Matches local telemetry | Reduce steps/output and finish/restart before runaway state | Medium-high |
| Compaction can lose state or loop | [Codex issue #35935](https://github.com/openai/codex/issues/35935), [OpenCode issue #27924](https://github.com/anomalyco/opencode/issues/27924) | Matches repeated high-compaction outliers | Do not treat compaction as a substitute for a bounded task | Medium |
| Recursive delegation can amplify work | [Codex issue #38989](https://github.com/openai/codex/issues/38989) | Matches local high-spawn outliers | Depth one and bounded child contracts | Medium-high |
| Small/local orchestrators struggle with implicit role boundaries | [OpenCode community report](https://www.reddit.com/r/opencodeCLI/comments/1uq54gx/cant_get_local_multiagent_orchestration_to_work/) | Opinion consistent with local critic results | Explicit goal/files/behavior/non-goals/check/return schema | Low-medium |

Community reports were used to identify patterns, not as authority. Five
MiniMax M2.7 critics were also run with a compact evidence packet. Their shared
recommendations (fewer roles, depth one, bounded output, deterministic worker
contracts) were accepted; unsupported proposals such as stale command caching
or attributing Codex metrics to OpenCode were rejected.

## Changes made

### Codex

- Global guidance now encodes one short search/output/delegation/validation
  contract instead of mandatory classification and handoff prose.
- `project_doc_max_bytes = 16384` and `tool_output_token_limit = 6000`.
- Base plugin surface disables browser, Chrome, Sites, Visualize, Calendar, and
  Slack. `design.config.toml` enables design/browser capabilities; the new
  `work.config.toml` enables Calendar and Slack; `notes.config.toml` remains the
  Obsidian overlay.
- Existing depth-one, concurrency-two, Luna explorer/reviewer design remains.
  No custom model-instructions replacement was added.

### OpenCode

- Custom roles are now build, plan, `explore-m2.7`, `explore-m2.5`,
  `worker-m2.7`, `worker-m3`, and `worker-luna`; children can be spawned from
  build without restarting OpenCode. Web/Android verifier and generic
  review/expert roles were removed.
- Delegation depth changed from two to one. Step ceilings are build 250, plan
  120, M2.7 worker 200, M3 worker 220, and Luna worker 160.
- The full user-authored skill catalog remains installed and is available to
  build, plan, and all workers.
- Build has all configured MCP tools. Sensitive auth/session path reads remain
  denied, and workers cannot launch nested children.
- Sensitive environment, SSH, Codex auth, and session-history reads are denied.
- Tool output changed from 128 KiB / 2,000 lines to 32 KiB / 500 lines.
- `/auto` and `/handoff` were removed. `/fix` and `/ui` now express direct,
  bounded outcomes.
- Installed schema compatibility is retained; filtered live config output
  confirms the source resolves to the intended V2 roles and permissions.

### NoxOrigin and dotfiles

- A compact NoxOrigin root router and scoped app/component guidance are active
  in the main checkout. They preserve ownership, tenancy, and risk-based
  validation while reducing the deepest instruction chain from 14,834 to 8,607
  bytes (42%).
- The main checkout API instructions no longer contain the plaintext local
  fixture credential.
- Dotfiles now forbids broad home scans and names the large/sensitive trees to
  exclude.

## Target architecture and local-model path

| Tier | Work | Minimum capability |
|---|---|---|
| A | Ambiguous architecture, cross-domain security/data changes, hard debugging, final integration | Strong planner/reviewer |
| B | Well-scoped feature or bug fix with explicit owners and tests | Medium coding worker |
| C | Exact-symbol exploration, mechanical edits, a named failing test, focused diff review, docs lookup | Small/local worker |

A worker contract is: goal; relevant files; required behavior; do-not-touch
list; one validation command; return files/results/blockers/assumptions. Model
IDs can change without changing that contract. No local inference endpoint was
running during the audit; MiniMax M2.7 was used as the available cheap critic.

## Validation and before/after indicators

The historical baseline cannot be replayed exactly without modifying product
code. Current validation therefore covers syntax, resolved configuration,
permission order, profile loading, repository diffs, and focused harness tests.
A clean historical comparison shows that bounded successful sessions can finish
in roughly 12 tools without compaction, while the outliers used thousands.

Static indicators after the change:

- Codex global guidance: 2,524 -> 1,916 bytes.
- NoxOrigin deepest instruction chain: 14,834 -> 8,607 bytes.
- OpenCode configured roles: 15 -> 7 practical roles; delegation depth: 2 -> 1.
- OpenCode build/M2.7-worker steps remain completion-oriented at 250/200.
- OpenCode authored skills remain available to build, plan, and workers.
- OpenCode output ceiling: 128 KiB / 2,000 lines -> 32 KiB / 500 lines.

## Remaining limitations

- Cumulative token telemetry is missing from 628 older Codex sessions and is
  not equivalent to billing. Cached input still pressures context but may have
  different monetary treatment.
- Regex-derived command/read/validation counts are estimates. Completion quality
  was inspected only for representative sessions, not semantically scored for
  all 841.
- Codex/OpenCode still resend substantial accumulated context per model step;
  local configuration cannot remove that platform behavior.
- OpenCode's configured MCP servers may still start even when permissions hide
  their tools. Tool-schema/runtime overhead should be remeasured after use.
- Raw `opencode debug config` output includes configured MCP header values.
  Validation now extracts source paths only; the existing affected credential
  should be rotated through the user-owned provider flow after this audit.
- Device and browser reliability depend on external processes. Permission
  routing reduces accidental use but cannot make flaky integrations reliable.

## Next experiment

For the next 20 completed tasks, capture the same metrics and compare by task
class against this baseline: tool calls, steps, failed calls, child sessions,
large outputs, compactions, validation tier, and accepted completion. The pass
criterion is at least 25% fewer median tool/step calls with no increase in user
corrections, reopened tasks, or missing risk-appropriate validation.
