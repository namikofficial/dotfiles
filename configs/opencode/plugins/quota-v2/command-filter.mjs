export function filterQuotaLayer(layer) {
  return {
    ...layer,
    commands: layer.commands.filter((command) => {
      const slashName = command.slashName ?? command.slash?.name
      return (
        slashName === undefined ||
        slashName === "quota" ||
        slashName === "quota_status"
      )
    }),
  }
}
