// Deterministic pre-edit safety hook.
// Blocks writes to secret/credential/sensitive paths.
//
// Severity model matches pre-shell-safety:
//   error     -> block (caller must change target)
//   warning   -> surface
//   advisory  -> log

const RULES = [
  {
    id: "edit/env-file",
    severity: "error",
    pattern: /(?:^|\/)\.env(?:\.[\w-]+)?$/i,
    description: ".env* files contain secrets and must not be written by agents",
  },
  {
    id: "edit/private-key",
    severity: "error",
    pattern: /(?:^|\/)(?:id_rsa|id_dsa|id_ecdsa|id_ed25519)(?:\.pub)?$/i,
    description: "SSH private key files must never be written by agents",
  },
  {
    id: "edit/key-file",
    severity: "error",
    pattern: /\.(?:key|pem|p12|pfx)$/i,
    description: ".key/.pem files typically contain secrets",
  },
  {
    id: "edit/ssh-dir",
    severity: "error",
    pattern: /\/\.ssh\//,
    description: "writes under ~/.ssh/ are blocked",
  },
  {
    id: "edit/private-key-block",
    severity: "error",
    pattern: /-----BEGIN (?:RSA |DSA |EC |OPENSSH |ENCRYPTED |)PRIVATE KEY-----/,
    description: "PEM private key block detected",
  },
  {
    id: "edit/gnupg",
    severity: "warning",
    pattern: /\/\.gnupg\//,
    description: "writes under ~/.gnupg/ — confirm intent",
  },
  {
    id: "edit/aws-credentials",
    severity: "error",
    pattern: /\/\.aws\/credentials$/i,
    description: "AWS credentials file",
  },
  {
    id: "edit/netrc",
    severity: "error",
    pattern: /\/\.netrc$/i,
    description: ".netrc contains plaintext credentials",
  },
]

const matchesAny = (target) => {
  for (const rule of RULES) {
    if (rule.pattern.test(target)) {
      return rule
    }
  }
  return null
}

const formatFinding = (rule, target) => ({
  rule: rule.id,
  severity: rule.severity,
  confidence: 0.98,
  file: target,
  line: 0,
  symbol: "(path)",
  evidence: target,
  suggestedInvestigation: rule.description,
})

const extractTarget = (input) => {
  // Different edit tools report the target path under different keys.
  const candidates = [
    input?.filePath,
    input?.path,
    input?.filepath,
    input?.target,
    input?.file,
  ]
  return candidates.find((c) => typeof c === "string" && c.length > 0) ?? ""
}

export const PreEditSafety = async () => {
  return {
    "file.edit": async (input, output) => {
      const target = extractTarget(input)
      if (!target) return

      const hit = matchesAny(target)
      if (!hit) return

      const finding = formatFinding(hit, target)
      if (output && typeof output === "object") {
        output.metadata = { ...(output.metadata || {}), safetyFinding: finding }
      }

      if (hit.severity === "error") {
        throw new Error(
          `[pre-edit-safety] BLOCKED ${finding.rule}: ${finding.suggestedInvestigation}\n` +
            `Target: ${target}`,
        )
      }
    },
    "file.write": async (input, output) => {
      const target = extractTarget(input)
      if (!target) return

      const hit = matchesAny(target)
      if (!hit) return

      const finding = formatFinding(hit, target)
      if (output && typeof output === "object") {
        output.metadata = { ...(output.metadata || {}), safetyFinding: finding }
      }

      if (hit.severity === "error") {
        throw new Error(
          `[pre-edit-safety] BLOCKED ${finding.rule}: ${finding.suggestedInvestigation}\n` +
            `Target: ${target}`,
        )
      }
    },
  }
}
