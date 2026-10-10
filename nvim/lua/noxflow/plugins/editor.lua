return {
  {
    "folke/snacks.nvim",
    priority = 1000,
    lazy = false,
    ---@type snacks.Config
    opts = {
      bigfile = { enabled = true, notify = false },
      -- Start screen: the handful of actions you need, with their keys.
      dashboard = {
        enabled = true,
        preset = {
          keys = {
            { icon = " ", key = "f", desc = "Find file", action = ":lua Snacks.picker.files()" },
            { icon = " ", key = "r", desc = "Recent files", action = ":lua Snacks.picker.recent()" },
            { icon = " ", key = "g", desc = "Search text in project", action = ":lua Snacks.picker.grep()" },
            { icon = " ", key = "e", desc = "File explorer", action = ":lua Snacks.explorer()" },
            { icon = " ", key = "p", desc = "Projects", action = ":lua Snacks.picker.projects()" },
            { icon = "󰋗 ", key = "?", desc = "Guide: how to use this setup", action = ":edit " .. vim.fn.stdpath("config") .. "/GUIDE.md" },
            { icon = "󰒲 ", key = "L", desc = "Plugins (Lazy)", action = ":Lazy" },
            { icon = " ", key = "q", desc = "Quit", action = ":qa" },
          },
        },
      },
      explorer = { enabled = true, replace_netrw = true, trash = true },
      indent = { enabled = true, animate = { enabled = false } },
      input = { enabled = true },
      notifier = { enabled = true, timeout = 3000 },
      -- Show files the way VS Code does: dotfiles (.env, .sops.yaml,
      -- .github/) and gitignored files are visible; .git itself stays hidden.
      -- In the explorer, gitignored entries are dimmed. Toggle inside any
      -- picker/explorer with  H  (hidden) and  I  (ignored).
      picker = {
        enabled = true,
        sources = {
          explorer = {
            hidden = true,
            ignored = true,
            exclude = { ".git" },
            follow_file = true,
            layout = { layout = { width = 34 } },
          },
          files = { hidden = true, ignored = false, exclude = { ".git" } },
          grep = { hidden = true, ignored = false, exclude = { ".git" } },
          smart = { hidden = true },
        },
      },
      quickfile = { enabled = true },
      scratch = { enabled = true },
      scope = { enabled = true },
      terminal = { enabled = true },
      animate = { enabled = false },
      scroll = { enabled = false },
      statuscolumn = { enabled = false },
      words = { enabled = false },
      styles = {
        notification = { wo = { winblend = 5 } },
        terminal = { wo = { winhighlight = "Normal:NormalFloat,FloatBorder:FloatBorder" } },
      },
    },
    keys = {
      { "<leader>e", function() Snacks.explorer() end, desc = "File explorer" },
      { "<leader><space>", function() Snacks.picker.smart() end, desc = "Smart files" },
      { "<leader>ff", function() Snacks.picker.files({ cwd = require("noxflow.utils").buf_root(0) }) end, desc = "Find files" },
      { "<leader>fg", function() Snacks.picker.grep({ cwd = require("noxflow.utils").buf_root(0) }) end, desc = "Live grep" },
      { "<leader>fb", function() Snacks.picker.buffers() end, desc = "Find buffers" },
      { "<leader>fr", function() Snacks.picker.recent() end, desc = "Recent files" },
      { "<leader>fp", function() Snacks.picker.projects() end, desc = "Projects" },
      { "<leader>fh", function() Snacks.picker.help() end, desc = "Help tags" },
      { "<leader>fc", function() Snacks.picker.files({ cwd = vim.fn.stdpath("config") }) end, desc = "Config files" },
      { "<leader>ss", function() Snacks.picker.lsp_symbols() end, desc = "Document symbols" },
      { "<leader>sS", function() Snacks.picker.lsp_workspace_symbols() end, desc = "Workspace symbols" },
      { "<leader>sw", function() Snacks.picker.grep_word({ cwd = require("noxflow.utils").buf_root(0) }) end, desc = "Search word" },
      { "<leader>gg", function() Snacks.lazygit() end, desc = "LazyGit" },
      { "<leader>tt", function() Snacks.terminal.toggle(nil, { cwd = require("noxflow.utils").buf_root(0), id = "shell:" .. require("noxflow.utils").buf_root(0) }) end, desc = "Project terminal" },
      { "<leader>tf", function() Snacks.terminal.toggle(nil, { cwd = require("noxflow.utils").buf_root(0), id = "shell-float:" .. require("noxflow.utils").buf_root(0), win = { style = "float" } }) end, desc = "Floating terminal" },
      { "<leader>bd", function() Snacks.bufdelete() end, desc = "Delete buffer" },
      { "<leader>bo", function() Snacks.bufdelete.other() end, desc = "Delete other buffers" },
      { "gd", function() Snacks.picker.lsp_definitions() end, desc = "Go to definition" },
      { "<leader>wv", "<cmd>vsplit<cr>", desc = "Vertical split" },
      { "<leader>ws", "<cmd>split<cr>", desc = "Horizontal split" },
      { "<leader>wq", "<cmd>close<cr>", desc = "Close window" },
    },
  },
  {
    "folke/which-key.nvim",
    event = "VeryLazy",
    opts = {
      delay = 300,
      spec = {
        { "<leader>f", group = "find" },
        { "<leader>s", group = "search" },
        { "<leader>g", group = "git" },
        { "<leader>c", group = "code" },
        { "<leader>x", group = "diagnostics" },
        { "<leader>a", group = "agents" },
        { "<leader>t", group = "terminal" },
        { "<leader>b", group = "buffers" },
        { "<leader>w", group = "windows" },
        { "<leader>T", group = "test" },
        { "<leader>d", group = "debug" },
        { "<leader>?", desc = "Keys for this buffer" },
        { "<leader>H", desc = "Guide (how to use this setup)" },
      },
    },
  },
  {
    "christoomey/vim-tmux-navigator",
    cmd = {
      "TmuxNavigateLeft",
      "TmuxNavigateDown",
      "TmuxNavigateUp",
      "TmuxNavigateRight",
      "TmuxNavigatePrevious",
    },
    keys = {
      { "<C-h>", "<cmd><C-U>TmuxNavigateLeft<cr>", desc = "Navigate left" },
      { "<C-j>", "<cmd><C-U>TmuxNavigateDown<cr>", desc = "Navigate down" },
      { "<C-k>", "<cmd><C-U>TmuxNavigateUp<cr>", desc = "Navigate up" },
      { "<C-l>", "<cmd><C-U>TmuxNavigateRight<cr>", desc = "Navigate right" },
      -- No terminal-mode copies: inside :terminal the shell needs Ctrl-h/j/k/l
      -- (backspace, accept-line, kill-line, clear). Leave with Ctrl-\ Ctrl-n
      -- first, then navigate.
    },
  },
  {
    "tpope/vim-sleuth",
    event = "BufReadPre",
  },
  {
    "windwp/nvim-autopairs",
    event = "InsertEnter",
    opts = {},
  },
}
