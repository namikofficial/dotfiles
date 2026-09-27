import { Plugin } from "@opencode/plugin/tui"
import { filterQuotaLayer } from "./command-filter.mjs"

const quotaPath = `${process.env.XDG_STATE_HOME || `${process.env.HOME}/.local/state`}/opencode/opencode-quota-v2/dist/tui-v2.js`
const { default: upstream } = await import(quotaPath)

export default Plugin.define({
  id: upstream.id,
  setup(context) {
    // The quota TUI plugin targets the v1 SDK, where config.providers() was
    // available. OpenCode v2 exposes provider.list() and returns provider
    // records directly, so provide the small compatibility surface it needs.
    const sdk = context.client as unknown as {
      config: Record<string, unknown>
      provider: { list: () => Promise<{ data?: Array<{ id: string }> }> }
    }
    const config = Object.fromEntries(
      Object.entries(sdk.config).map(([key, value]) => [
        key,
        typeof value === "function" ? value.bind(sdk.config) : value,
      ]),
    ) as Record<string, unknown>
    config.providers = async () => {
      const response = await sdk.provider.list()
      return { data: { providers: response.data ?? [] } }
    }
    const client = { ...context.client, config } as typeof context.client

    return upstream.setup({
      ...context,
      client,
      keymap: {
        ...context.keymap,
        layer: (build) => context.keymap.layer(() => filterQuotaLayer(build())),
      },
    })
  },
})
