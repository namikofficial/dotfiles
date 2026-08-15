return {
  {
    "saghen/blink.cmp",
    event = "InsertEnter",
    dependencies = {
      "saghen/blink.lib",
      "rafamadriz/friendly-snippets",
    },
    build = function()
      require("blink.cmp").build():pwait()
    end,
    opts = {
      keymap = { preset = "super-tab" },
      completion = {
        documentation = { auto_show = false },
        list = { selection = { preselect = false, auto_insert = false } },
      },
      snippets = { preset = "default" },
      fuzzy = { implementation = "rust" },
      sources = { default = { "lsp", "path", "snippets", "buffer" } },
      signature = { enabled = true },
    },
  },
  {
    "MagicDuck/grug-far.nvim",
    cmd = { "GrugFar" },
    keys = {
      { "<leader>sr", function() require("grug-far").open() end, desc = "Search and replace" },
      { "<leader>sr", function() require("grug-far").with_visual_selection() end, mode = "v", desc = "Replace selection" },
    },
    opts = {
      transient = true,
      engines = { ripgrep = { extraArgs = { "--hidden" } } },
    },
  },
  {
    "folke/flash.nvim",
    event = "VeryLazy",
    opts = {},
    keys = {
      { "s", mode = { "n", "x", "o" }, function() require("flash").jump() end, desc = "Flash jump" },
      { "S", mode = { "n", "x", "o" }, function() require("flash").treesitter() end, desc = "Flash Treesitter" },
      { "r", mode = "o", function() require("flash").remote() end, desc = "Remote Flash" },
    },
  },
  {
    "nvim-mini/mini.nvim",
    event = "VeryLazy",
    config = function()
      require("mini.ai").setup({})
      require("mini.surround").setup({
        mappings = {
          add = "gsa",
          delete = "gsd",
          find = "gsf",
          find_left = "gsF",
          highlight = "gsh",
          replace = "gsr",
          update_n_lines = "gsn",
        },
      })
    end,
  },
}
