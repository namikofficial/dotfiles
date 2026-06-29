export const StripReasoningHistory = async () => {
  return {
    "experimental.chat.messages.transform": async (_input, output) => {
      for (const message of output.messages) {
        message.parts = message.parts.filter((part) => part.type !== "reasoning")
      }
    },
  }
}
