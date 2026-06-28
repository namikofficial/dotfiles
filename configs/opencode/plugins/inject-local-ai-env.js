export const InjectLocalAiEnv = async () => {
  return {
    "shell.env": async (input, output) => {
      output.env.LLM_BASE_URL = process.env.LLM_BASE_URL || "http://127.0.0.1:8080/v1"
      output.env.LLM_HEALTH_ENDPOINT =
        process.env.LLM_HEALTH_ENDPOINT || "http://127.0.0.1:8080/v1/models"
      output.env.OPENCODE_DEFAULT_MODEL =
        process.env.OPENCODE_DEFAULT_MODEL || "llamacpp/qwen3-router"
      output.env.OPENCODE_PROJECT_ROOT = input.cwd
    },
  }
}
