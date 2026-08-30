// Read-only, cheap diagnostics after a file save. Expensive project checks belong to /verify.
export const PostEditDiagnostics = {
  name: "post-edit-diagnostics",
  description: "Run targeted non-mutating diagnostics after edits",
  "file.save": async ({ path, $, directory }) => {
    if (!/\.(ts|tsx|js|jsx|mjs|cjs|json|kt|kts)$/.test(path)) return

    try {
      await $`git -C ${directory} diff --check -- ${path}`.quiet()
    } catch {}

    if (/\.(ts|tsx|js|jsx|mjs|cjs)$/.test(path)) {
      try {
        await $`pnpm --dir ${directory} exec eslint --no-warn-ignored ${path}`.quiet()
      } catch {}
    }
  },
}
