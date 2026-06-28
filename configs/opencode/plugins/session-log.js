export const SessionLog = async ({ client, directory, worktree }) => {
  return {
    "session.created": async () => {
      await client.app.log({
        body: {
          service: "session-log",
          level: "info",
          message: "OpenCode session started",
          extra: {
            directory,
            worktree,
          },
        },
      })
    },
  }
}
