local opt = vim.opt

vim.g.mapleader = " "
vim.g.maplocalleader = " "
vim.g.loaded_node_provider = 0
vim.g.loaded_python3_provider = 0
vim.g.loaded_perl_provider = 0
vim.g.loaded_ruby_provider = 0

opt.number = true
opt.relativenumber = true
opt.mouse = "a"
opt.showmode = false
opt.laststatus = 3
opt.signcolumn = "yes"
opt.termguicolors = true
opt.cursorline = true
opt.cursorlineopt = "screenline,number"
opt.wrap = false
opt.scrolloff = 8
opt.sidescrolloff = 8
opt.splitright = true
opt.splitbelow = true
opt.ignorecase = true
opt.smartcase = true
opt.inccommand = "split"
opt.updatetime = 250
opt.timeoutlen = 300
opt.completeopt = { "menu", "menuone", "noselect" }
opt.clipboard = "unnamedplus"
opt.undofile = true
opt.undolevels = 10000
opt.history = 1000
opt.pumheight = 12
opt.splitkeep = "screen"
opt.winborder = "rounded"
opt.shortmess:append({ I = true, c = true })
opt.fillchars = { eob = " ", fold = " ", foldopen = "▾", foldclose = "▸", foldsep = " " }
opt.expandtab = true
opt.shiftwidth = 2
opt.tabstop = 2
opt.softtabstop = 2
opt.smartindent = true
