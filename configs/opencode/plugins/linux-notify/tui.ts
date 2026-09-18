import { Plugin } from "@opencode/plugin/tui"

function notify(title: string, body: string) {
  try {
    const child = Bun.spawn(["notify-send", title, body], { stdout: "ignore", stderr: "ignore" })
    child.unref()
  } catch {
    // Desktop notifications are optional; never interrupt the TUI.
  }
}

export default Plugin.define({
  id: "nox.linux-notify",
  setup(context) {
    const directory = context.location?.directory ?? process.cwd()
    const stop = [
      context.data.on("session.created", () => notify("OpenCode", `Session started in ${directory}`)),
      context.data.on("session.idle", () => notify("OpenCode idle", directory)),
      context.data.on("permission.asked", () => notify("OpenCode needs approval", directory)),
    ]
    return () => stop.forEach((dispose) => dispose())
  },
})
