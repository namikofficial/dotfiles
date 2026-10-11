#!/usr/bin/env bash
# check-noxflow-plan.sh — assert the repair plan's numbers against the tree.
#
# Why this exists: docs/NOXFLOW_REPAIR_PLAN.md records measurements — QML line
# counts, per-file sizes, an acceptance verdict. Those are prose, and prose goes
# stale. During the phase 1 re-verification the plan's 0.5 log was corrected to
# the current numbers while the Phase 2 acceptance block a few hundred lines
# below kept quoting the superseded ones (12,876 / 16,792 / 117 files). Both
# were "true" when written; only one was true when read. A stale figure in a
# status document is worse than no figure, because it reads as current.
#
# So the numbers that appear in the plan are asserted here against what tokei
# and wc actually report. If the tree moves, this fails and names the line.
#
# What it checks:
#   1. The header status does not claim "complete" while a deviation is open.
#   2. The QML code/raw/file counts in 0.5 match `tokei shell/noxflow`.
#   3. The pre-repair baseline row matches the tree at HEAD~1, when that
#      commit exists (skipped otherwise).
#   4. Every file in bar/ and island/ is within the plan's 350-line cap, and
#      the size IslandHost is recorded at is its real size.
#   5. The gate block scopes the journal count per instance rather than with -b.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_DIR"

PLAN="docs/NOXFLOW_REPAIR_PLAN.md"
fail=0

ok() { printf 'OK    %s\n' "$1"; }
bad() {
  printf 'FAIL  %s\n' "$1"
  fail=1
}

[ -f "$PLAN" ] || {
  printf 'FAIL  %s not found\n' "$PLAN"
  exit 1
}

if ! command -v tokei >/dev/null 2>&1; then
  printf 'SKIP  tokei not installed; cannot verify the plan line counts\n'
  exit 0
fi

# ── 1. The status line ───────────────────────────────────────────────────────
status_line="$(sed -n '3p' "$PLAN")"
if grep -qE '^Status: complete' <<<"$status_line"; then
  bad "the plan declares 'complete' on line 3; it has an open deviation, so say what is open"
else
  ok "status line does not overclaim"
fi

# ── 2. The 0.5 measurement table against the live tree ───────────────────────
row="$(grep -E '^\| now \(committed\) \|' "$PLAN" | head -1 || true)"
if [ -z "$row" ]; then
  bad "no '| now (committed) |' row in the 0.5 table"
else
  claimed_files="$(sed -E 's/^\| now \(committed\) \| \*\*([0-9,]+)\*\*.*/\1/' <<<"$row" | tr -d ,)"
  claimed_raw="$(sed -E 's/^\| now \(committed\) \| \*\*[0-9,]+\*\* \| \*\*([0-9,]+)\*\*.*/\1/' <<<"$row" | tr -d ,)"
  claimed_code="$(sed -E 's/^\| now \(committed\) \| \*\*[0-9,]+\*\* \| \*\*[0-9,]+\*\* \| \*\*([0-9,]+)\*\*.*/\1/' <<<"$row" | tr -d ,)"

  read -r real_files real_raw real_code _ < <(
    tokei shell/noxflow 2>/dev/null | awk '$1 == "QML" { print $2, $3, $4; exit }'
  )

  for pair in "files:$claimed_files:$real_files" "raw:$claimed_raw:$real_raw" "code:$claimed_code:$real_code"; do
    label="${pair%%:*}"
    rest="${pair#*:}"
    claimed="${rest%%:*}"
    real="${rest#*:}"
    if [ "$claimed" = "$real" ]; then
      ok "QML $label matches the tree ($real)"
    else
      bad "QML $label: the plan says $claimed, tokei says ${real:-<none>}"
    fi
  done
fi

# ── 3. The pre-repair baseline row, when HEAD~1 exists ───────────────────────
base_row="$(grep -E '^\| pre-repair \(`[0-9a-f]+`\)' "$PLAN" | head -1 || true)"
if [ -z "$base_row" ]; then
  bad "no '| pre-repair (<commit>) |' row in the 0.5 table"
else
  # Pinned to an explicit commit, never HEAD~1: relative refs move as soon as
  # anything else is committed, which silently re-reads the repair commit as
  # the baseline. The first version of this check used HEAD~1 and failed the
  # moment a second commit landed.
  # Capture only what is inside the backticks: a loose [0-9a-f] match finds
  # "e" inside "pre-repair" long before it reaches the hash.
  base_commit="$(sed -E 's/^\| pre-repair \(`([0-9a-f]+)`\).*/\1/' <<<"$base_row")"
  if ! git rev-parse --verify --quiet "${base_commit}^{commit}" >/dev/null; then
    bad "the plan pins the pre-repair baseline to $base_commit, which is not a commit here"
    base_commit=""
  fi
fi

if [ -n "${base_commit:-}" ]; then
  # The baseline row is not bolded; take its last (code) field.
  claimed_code="$(awk -F'|' '{ gsub(/[ *,]/, "", $5); print $5 }' <<<"$base_row")"
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  git archive "$base_commit" shell/noxflow 2>/dev/null | tar -x -C "$tmp"
  real_code="$(tokei "$tmp/shell/noxflow" 2>/dev/null | awk '$1 == "QML" { print $4; exit }')"
  if [ "$claimed_code" = "$real_code" ]; then
    ok "pre-repair baseline matches $base_commit ($real_code)"
  else
    bad "pre-repair baseline: the plan says $claimed_code, $base_commit says ${real_code:-<none>}"
  fi
fi

# ── 4. The 350-line cap ─────────────────────────────────────────────────────
over="$(find shell/noxflow/bar shell/noxflow/island \( -name '*.qml' -o -name '*.js' \) -print0 |
  xargs -0 wc -l 2>/dev/null | awk -v c=350 '$1 > c && $2 != "total"')"
if [ -z "$over" ]; then
  ok "no file in bar/ or island/ exceeds the 350-line cap"
else
  bad "files over the plan's 350-line cap:"
  printf '%s\n' "$over"
fi

host_lines="$(wc -l <shell/noxflow/island/IslandHost.qml)"
# `tail -1`, not `head -1`: the matched text also contains the 1146 it replaced.
claimed_host="$(grep -oE 'went 1146 → \*\*[0-9]+\*\*' "$PLAN" | head -1 | grep -oE '[0-9]+' | tail -1 || true)"
if [ -z "$claimed_host" ]; then
  bad "the plan does not record an IslandHost.qml size"
elif [ "$claimed_host" = "$host_lines" ]; then
  ok "IslandHost.qml size matches the plan ($host_lines)"
else
  bad "IslandHost.qml: the plan says $claimed_host, wc says $host_lines"
fi

# ── 5. The journal gate must not accumulate across the whole boot ───────────
if grep -qE "journalctl .*-u noxflow-shell .*-b" "$PLAN"; then
  bad "the phase gate still uses journalctl -b, which accumulates every instance since boot"
else
  ok "the phase gate scopes the journal count per instance"
fi

printf '\n'
if [ "$fail" -eq 0 ]; then
  printf 'PASS noxflow plan matches the tree\n'
else
  printf 'FAIL noxflow plan has drifted from the tree\n'
  exit 1
fi
