const EDIT_RULES = [
  { id: "edit/env-file", severity: "error", pattern: /(?:^|\/)\.env(?:\.[\w-]+)?$/i, description: ".env* files contain secrets" },
  { id: "edit/private-key", severity: "error", pattern: /(?:^|\/)(?:id_rsa|id_dsa|id_ecdsa|id_ed25519)(?:\.pub)?$/i, description: "SSH private key files must never be written" },
  { id: "edit/key-file", severity: "error", pattern: /\.(?:key|pem|p12|pfx)$/i, description: "credential or private-key file" },
  { id: "edit/ssh-dir", severity: "error", pattern: /\/\.ssh\//, description: "writes under ~/.ssh/ are blocked" },
  { id: "edit/private-key-block", severity: "error", pattern: /-----BEGIN (?:RSA |DSA |EC |OPENSSH |ENCRYPTED |)PRIVATE KEY-----/, description: "private key block detected" },
  { id: "edit/gnupg", severity: "warning", pattern: /\/\.gnupg\//, description: "writes under ~/.gnupg/ need confirmation" },
  { id: "edit/aws-credentials", severity: "error", pattern: /\/\.aws\/credentials$/i, description: "AWS credentials file" },
  { id: "edit/netrc", severity: "error", pattern: /\/\.netrc$/i, description: ".netrc contains plaintext credentials" },
]

const SHELL_RULES = [
  { id: "shell/rm-rf", severity: "error", pattern: /\brm\s+(?:-\w*r\w*f\w*|--recursive\s+--force|-rf|-fr)\s+\/(?:\s|$|;|\.)/, description: "rm -rf at filesystem root" },
  { id: "shell/rm-rf-relative", severity: "error", pattern: /\brm\s+(?:-\w*r\w*f\w*|--recursive\s+--force|-rf|-fr)\s+\.{1,2}(?:\s|$|;|\/)/, description: "rm -rf targeting a parent directory" },
  { id: "shell/drop-table", severity: "error", pattern: /\bDROP\s+TABLE\b/i, description: "DROP TABLE is destructive" },
  { id: "shell/delete-without-where", severity: "error", pattern: /\bDELETE\s+FROM\s+\w+\s*;/i, description: "DELETE FROM without WHERE is destructive" },
  { id: "shell/docker-system-prune", severity: "warning", pattern: /\bdocker\s+system\s+prune\b/, description: "Docker system prune removes unused resources" },
  { id: "shell/kubectl-delete", severity: "warning", pattern: /\bkubectl\s+delete\b/, description: "confirm the Kubernetes namespace and resource" },
  { id: "shell/terraform-destroy", severity: "error", pattern: /\bterraform\s+destroy\b/, description: "terraform destroy removes managed infrastructure" },
  { id: "shell/git-force-push", severity: "warning", pattern: /\bgit\s+push\s+(?:--force(?:-with-lease)?|-f)\b/, description: "confirm the target branch and lease" },
  { id: "shell/chmod-777", severity: "warning", pattern: /\bchmod\s+(-R\s+)?777\b/, description: "chmod 777 is unsafe" },
  { id: "shell/curl-pipe-shell", severity: "error", pattern: /\b(curl|wget)\b[^|]*\|\s*(?:sudo\s+)?(?:ba)?sh\b/, description: "unverified remote shell execution" },
]

function findRule(rules, value) {
  return rules.find((rule) => rule.pattern.test(value)) ?? null
}

export function findEditSafetyIssue(target) {
  return typeof target === "string" ? findRule(EDIT_RULES, target) : null
}

export function findShellSafetyIssue(command) {
  return typeof command === "string" ? findRule(SHELL_RULES, command) : null
}

export function getEditTarget(input) {
  const candidates = [input?.filePath, input?.path, input?.filepath, input?.target, input?.file]
  return candidates.find((candidate) => typeof candidate === "string" && candidate.length > 0) ?? ""
}
