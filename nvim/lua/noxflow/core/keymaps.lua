local map = vim.keymap.set

map({ "n", "i", "v" }, "<C-s>", "<cmd>update<cr>", { desc = "Save buffer" })
map("n", "<leader>q", "<cmd>quit<cr>", { desc = "Quit window" })
map("n", "<leader>Q", "<cmd>qa!<cr>", { desc = "Quit all" })
map("n", "<Esc>", "<cmd>nohlsearch<cr>", { desc = "Clear search highlight" })

-- ── VS Code muscle memory ───────────────────────────────────────────────────
-- Ctrl-p quick open, Ctrl-/ toggle comment, Alt-Up/Down move lines.
map("n", "<C-p>", function() Snacks.picker.files() end, { desc = "Quick open file" })
map("n", "<C-/>", "gcc", { remap = true, desc = "Toggle comment" })
map("v", "<C-/>", "gc", { remap = true, desc = "Toggle comment" })
-- Terminals without the kitty keyboard protocol send Ctrl-/ as Ctrl-_.
map("n", "<C-_>", "gcc", { remap = true, desc = "Toggle comment" })
map("v", "<C-_>", "gc", { remap = true, desc = "Toggle comment" })
map("n", "<A-Down>", "<cmd>m .+1<cr>==", { desc = "Move line down" })
map("n", "<A-Up>", "<cmd>m .-2<cr>==", { desc = "Move line up" })
map("v", "<A-Down>", ":m '>+1<cr>gv=gv", { desc = "Move selection down" })
map("v", "<A-Up>", ":m '<-2<cr>gv=gv", { desc = "Move selection up" })
map("v", "<", "<gv", { desc = "Indent left (keep selection)" })
map("v", ">", ">gv", { desc = "Indent right (keep selection)" })

-- ── Learning aids ───────────────────────────────────────────────────────────
-- <leader>? lists every key that works in this buffer; <leader>sk searches
-- all keymaps by description; <leader>H opens the NoxFlow nvim guide.
map("n", "<leader>?", function() require("which-key").show({ global = false }) end, { desc = "Keys for this buffer" })
map("n", "<leader>sk", function() Snacks.picker.keymaps() end, { desc = "Search keymaps" })
map("n", "<leader>sc", function() Snacks.picker.commands() end, { desc = "Search commands" })
map("n", "<leader>H", function()
  vim.cmd.edit(vim.fn.stdpath("config") .. "/GUIDE.md")
end, { desc = "NoxFlow nvim guide" })
