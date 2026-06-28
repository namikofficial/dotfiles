const safeNotify = async ($, title, body) => {
  try {
    await $`notify-send ${title} ${body}`
  } catch {}
}

export const LinuxNotify = async ({ $, directory }) => {
  return {
    event: async ({ event }) => {
      if (event.type === "session.idle") {
        await safeNotify($, "OpenCode idle", directory)
      }
      if (event.type === "permission.asked") {
        await safeNotify($, "OpenCode needs approval", directory)
      }
    },
  }
}
