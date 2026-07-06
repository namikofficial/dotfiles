// biome-format.js — OpenCode plugin: run `biome check --write` on save
// Install: place in ~/.config/opencode/plugins/ (already in plugins.path config)
// Requires: biome installed (pnpm add -g @biomejs/biome or via project devDependency)

export const BiomeFormat = {
  name: "biome-format",
  description: "Run `biome check --write` on file save for TS/JS/JSON files",

  "file.save": async ({ path }) => {
    // Only act on source files that Biome can format
    if (!/\.(ts|tsx|js|jsx|mjs|cjs|json)$/.test(path)) {
      return;
    }

    // Skip files outside a project (no package.json nearby)
    const { $ } = await import("bun");
    try {
      await $`biome check --write --no-errors-on-unmatched ${path}`.quiet();
    } catch {
      // Biome not on PATH or file doesn't match biome config — silent
    }
  },
};
