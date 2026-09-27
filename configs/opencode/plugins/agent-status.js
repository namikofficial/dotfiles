// agent-status.js — OpenCode plugin: expose agent lifecycle events for TUI status
export const AgentStatus = async ({ client }) => {
  return {
    "agent.started": async ({ agent, directory }) => {
      await client.app.status({
        body: {
          service: "agent-status",
          level: "info",
          message: `Agent started: ${agent}`,
          extra: { agent, directory },
        },
      })
    },
    "agent.finished": async ({ agent, directory, result }) => {
      await client.app.status({
        body: {
          service: "agent-status",
          level: "info",
          message: `Agent finished: ${agent}`,
          extra: { agent, directory, result },
        },
      })
    },
  }
}
