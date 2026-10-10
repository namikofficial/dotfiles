return {
  {
    "catppuccin/nvim",
    name = "catppuccin",
    priority = 1000,
    opts = {
      flavour = "macchiato",
      transparent_background = true,
      dim_inactive = { enabled = true, shade = "dark", percentage = 0.10 },
      integrations = {
        blink_cmp = true,
        gitsigns = true,
        mason = false,
        snacks = true,
        trouble = true,
        which_key = true,
      },
    },
    config = function(_, opts)
      require("catppuccin").setup(opts)
      vim.cmd.colorscheme("catppuccin")
    end,
  },
  {
    "nvim-lualine/lualine.nvim",
    event = "VeryLazy",
    dependencies = { "nvim-tree/nvim-web-devicons" },
    opts = {
      options = {
        theme = "catppuccin",
        globalstatus = true,
        component_separators = "",
        section_separators = "",
      },
      sections = {
        lualine_a = { "mode" },
        lualine_b = { "branch", "diff", "diagnostics" },
        lualine_c = { { "filename", path = 1 } },
        -- lsp_status: which language servers are attached to this buffer.
        lualine_x = { "lsp_status", "filetype" },
        lualine_y = { "progress" },
        lualine_z = { "location" },
      },
    },
  },
  {
    -- Editor tabs, like VS Code. Shift-h / Shift-l move between them,
    -- <leader>bd closes one, <leader>bp pins it.
    "akinsho/bufferline.nvim",
    version = "*",
    event = "VeryLazy",
    dependencies = { "nvim-tree/nvim-web-devicons" },
    keys = {
      { "<S-h>", "<cmd>BufferLineCyclePrev<cr>", desc = "Previous tab" },
      { "<S-l>", "<cmd>BufferLineCycleNext<cr>", desc = "Next tab" },
      { "<leader>bp", "<cmd>BufferLineTogglePin<cr>", desc = "Pin tab" },
      { "<leader>bP", "<cmd>BufferLineGroupClose ungrouped<cr>", desc = "Close unpinned tabs" },
      { "<leader>bl", "<cmd>BufferLineCloseLeft<cr>", desc = "Close tabs to the left" },
      { "<leader>br", "<cmd>BufferLineCloseRight<cr>", desc = "Close tabs to the right" },
    },
    opts = {
      options = {
        close_command = function(n) Snacks.bufdelete(n) end,
        right_mouse_command = function(n) Snacks.bufdelete(n) end,
        diagnostics = "nvim_lsp",
        always_show_bufferline = false,
        separator_style = "thin",
        show_buffer_close_icons = false,
        -- Leave room for the explorer so tabs line up with the editor.
        offsets = { { filetype = "snacks_layout_box", text = "Explorer", highlight = "Directory", separator = true } },
      },
    },
  },
}
