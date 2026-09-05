// Deterministic pre-shell safety hook.
// Blocks (or surfaces) bash commands matching destructive patterns.
// Severity model:
//   error     -> block (caller must change command)
//   warning   -> surface to M3 / require acknowledgement
//   advisory  -> log only, included in verification report
//
// This plugin does NOT prompt the user; it returns a structured finding that the
// build agent surfaces in its verification report. The plugin layer cannot directly
// halt execution in this OpenCode version, so we use throw to abort the bash call.

const RULES = [
  {
    id: "shell/rm-rf",
    severity: "error",
    pattern: /\brm\s+(?:-\w*r\w*f\w*|--recursive\s+--force|-rf|-fr)\s+\/(?:\s|$|;|\.)/,
    description: "rm -rf at filesystem root",
  },
  {
    id: "shell/rm-rf-relative",
    severity: "error",
    pattern: /\brm\s+(?:-\w*r\w*f\w*|--recursive\s+--force|-rf|-fr)\s+\.{1,2}(?:\s|$|;|\/)/,
    description: "rm -rf targeting parent directory",
  },
  {
    id: "shell/drop-table",
    severity: "error",
    pattern: /\bDROP\s+TABLE\b/i,
    description: "DROP TABLE — destructive schema change",
  },
  {
    id: "shell/delete-without-where",
    severity: "error",
    pattern: /\bDELETE\s+FROM\s+\w+\s*;/i,
    description: "DELETE FROM <table> without WHERE clause",
  },
  {
    id: "shell/docker-system-prune",
    severity: "warning",
    pattern: /\bdocker\s+system\s+prune\b/,
    description: "Docker system prune — destroys all stopped containers and unused images",
  },
  {
    id: "shell/kubectl-delete",
    severity: "warning",
    pattern: /\bkubectl\s+delete\b/,
    description: "kubectl delete — confirm namespace and resource",
  },
  {
    id: "shell/terraform-destroy",
    severity: "error",
    pattern: /\bterraform\s+destroy\b/,
    description: "terraform destroy — destroys managed infrastructure",
  },
  {
    id: "shell/git-force-push",
    severity: "warning",
    pattern: /\bgit\s+push\s+(?:--force(?:-with-lease)?|-f)\b/,
    description: "git push --force — confirm target branch and lease",
  },
  {
    id: "shell/chmod-777",
    severity: "warning",
    pattern: /\bchmod\s+(-R\s+)?777\b/,
    description: "chmod 777 — security smell",
  },
  {
    id: "shell/curl-pipe-shell",
    severity: "error",
    pattern: /\b(curl|wget)\b[^|]*\|\s*(?:sudo\s+)?(?:ba)?sh\b/,
    description: "curl|sh or wget|sh — unverified remote execution",
  },
]

const matchesAny = (cmd) => {
  for (const rule of RULES) {
    if (rule.pattern.test(cmd)) {
      return rule
    }
  }
  return null
}

const formatFinding = (rule, command) => ({
  rule: rule.id,
  severity: rule.severity,
  confidence: 0.95,
  file: "(bash)",
  line: 0,
  symbol: "(shell)",
  evidence: command.length > 200 ? command.slice(0, 200) + "…" : command,
  suggestedInvestigation: rule.description,
})

export const PreShellSafety = async () => {
  return {
    "shell.execute": async (input, output) => {
      // `input` typically contains the args; the actual command string can be in
      // input.command, input.args, or constructed from args. We try a few shapes.
      const commandCandidates = []
      if (typeof input?.command === "string") commandCandidates.push(input.command)
      if (Array.isArray(input?.args)) commandCandidates.push(input.args.join(" "))
      if (typeof input?.args === "string") commandCandidates.push(input.args)
      if (typeof input === "string") commandCandidates.push(input)

      const command = commandCandidates.find((c) => typeof c === "string" && c.length > 0) ?? ""
      if (!command) return

      const hit = matchesAny(command)
      if (!hit) return

      const finding = formatFinding(hit, command)
      // Surface via output metadata so the agent sees it; abort on error severity.
      if (output && typeof output === "object") {
        output.metadata = { ...(output.metadata || {}), safetyFinding: finding }
      }

      if (hit.severity === "error") {
        throw new Error(
          `[pre-shell-safety] BLOCKED ${finding.rule}: ${finding.suggestedInvestigation}\n` +
            `Evidence: ${finding.evidence}`,
        )
      }
      // warning/advisory: do not throw; let the call proceed but the finding is
      // attached to output.metadata for the agent to acknowledge or surface.
    },
  }
}
