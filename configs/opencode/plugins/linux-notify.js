const safeNotify = async ($, title, body) => {
  try {
    await $`notify-send ${title} ${body}`
  } catch {}
}

export const LinuxNotify = async ({ $, directory }) => {
  return {
    event: async ({ event }) => {
      switch (event.type) {
        case "session.started":
          await safeNotify($, "OpenCode", "Session started in " + directory)
          break
        case "session.idle":
          await safeNotify($, "OpenCode idle", directory)
          break
        case "agent.started":
          await safeNotify($, "Agent: " + (event.agent || "unknown"), directory)
          break
        case "permission.asked":
          await safeNotify($, "OpenCode needs approval", directory)
          break
        case "tool.denied":
          await safeNotify($, "Tool denied", event.tool || "unknown")
          break
        case "compaction.triggered":
          await safeNotify($, "OpenCode", "Compaction triggered")
          break
      }
    },
  }
}
