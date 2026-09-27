import { findEditSafetyIssue, findShellSafetyIssue, getEditTarget } from "../safety-rules.js"

const editTools = new Set(["write", "edit", "patch", "apply_patch"])

function reject(prefix, finding, evidence) {
  throw new Error(`[${prefix}] ${finding.id}: ${finding.description}\nEvidence: ${evidence}`)
}

export default {
  id: "nox.safety-guards",
  async setup(ctx) {
    await ctx.tool.hook("execute.before", (event) => {
      if (!editTools.has(event.tool)) return
      const target = getEditTarget(event.input)
      if (!target) return
      const finding = findEditSafetyIssue(target)
      if (!finding) return
      if (finding.severity === "error") reject("pre-edit-safety", finding, target)
      console.warn(`[pre-edit-safety] ${finding.id}: ${finding.description}`)
    })

    await ctx.shell.hook("create.before", (event) => {
      const finding = findShellSafetyIssue(event.command)
      if (!finding) return
      if (finding.severity === "error") reject("pre-shell-safety", finding, event.command.slice(0, 200))
      console.warn(`[pre-shell-safety] ${finding.id}: ${finding.description}`)
    })
  },
}
