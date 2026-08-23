local function project_root()
  return require("noxflow.utils").buf_root(0)
end

local function toggle_agent(command)
  local root = project_root()
  Snacks.terminal.toggle(command, {
    cwd = root,
    id = command .. ":" .. root,
    win = { style = "float" },
  })
end

return {
  {
    "folke/snacks.nvim",
    keys = {
      {
        "<leader>aa",
        function()
          vim.ui.select({ "OpenCode", "Codex" }, { prompt = "Agent" }, function(choice)
            if choice == "OpenCode" then
              toggle_agent("opencode")
            elseif choice == "Codex" then
              toggle_agent("codex")
            end
          end)
        end,
        desc = "Choose agent",
      },
      { "<leader>ao", function() toggle_agent("opencode") end, desc = "OpenCode" },
      { "<leader>ac", function() toggle_agent("codex") end, desc = "Codex" },
    },
  },
  {
    "nickjvandyke/opencode.nvim",
    version = "*",
    keys = {
      {
        "<leader>ax",
        function()
          require("opencode").ask("@this: ")
        end,
        mode = { "n", "x" },
        desc = "Ask OpenCode about context",
      },
      {
        "<leader>as",
        function()
          require("opencode").select()
        end,
        mode = { "n", "x" },
        desc = "Select OpenCode action",
      },
    },
    init = function()
      vim.g.opencode_opts = vim.g.opencode_opts or {}
    end,
  },
}
