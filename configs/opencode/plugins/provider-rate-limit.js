import { mkdir, readFile, rm, stat, writeFile } from "node:fs/promises"
import { join } from "node:path"
import { tmpdir } from "node:os"

const stateDir = join(tmpdir(), "opencode-provider-rate-limit")
const defaults = {
  google: 30000,
  cerebras: 90000,
}

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms))

const providerID = (input) => input.provider?.info?.id || input.model?.providerID

const intervalFor = (provider) => {
  const value = Number(process.env[`OPENCODE_RATE_LIMIT_${provider.toUpperCase()}_MS`])
  return Number.isFinite(value) && value >= 0 ? value : defaults[provider]
}

const withLock = async (provider, callback) => {
  const lockDir = join(stateDir, `${provider}.lock`)

  for (;;) {
    try {
      await mkdir(lockDir, { recursive: false })
      break
    } catch (error) {
      if (error?.code !== "EEXIST") throw error
      try {
        const lock = await stat(lockDir)
        if (Date.now() - lock.mtimeMs > 300000) {
          await rm(lockDir, { recursive: true, force: true })
          continue
        }
      } catch (statError) {
        if (statError?.code !== "ENOENT") throw statError
      }
      await sleep(250)
    }
  }

  try {
    return await callback()
  } finally {
    await rm(lockDir, { recursive: true, force: true })
  }
}

const throttle = async (provider) => {
  await mkdir(stateDir, { recursive: true })

  await withLock(provider, async () => {
    const stateFile = join(stateDir, `${provider}.json`)
    const intervalMs = intervalFor(provider)
    const now = Date.now()
    let nextAt = 0

    try {
      nextAt = JSON.parse(await readFile(stateFile, "utf8")).nextAt || 0
    } catch (error) {
      if (error?.code !== "ENOENT") throw error
    }

    if (nextAt > now) {
      await sleep(nextAt - now)
    }

    await writeFile(stateFile, JSON.stringify({ nextAt: Date.now() + intervalMs }))
  })
}

export const ProviderRateLimit = async () => {
  return {
    "chat.params": async (input) => {
      const provider = providerID(input)
      if (provider !== "google" && provider !== "cerebras") return

      await throttle(provider)
    },
  }
}
