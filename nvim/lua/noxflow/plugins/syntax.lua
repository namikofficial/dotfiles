return {
  {
    "nvim-treesitter/nvim-treesitter",
    lazy = false,
    build = ":TSUpdate",
    config = function()
      local treesitter = require("nvim-treesitter")
      local languages = {
        "bash",
        "css",
        "dockerfile",
        "html",
        "javascript",
        "json",
        "lua",
        "markdown",
        "markdown_inline",
        "rust",
        "toml",
        "tsx",
        "typescript",
        "yaml",
      }

      treesitter.setup({ install_dir = vim.fn.stdpath("data") .. "/site" })
      if vim.fn.executable("tree-sitter") == 1 then
        vim.defer_fn(function()
          treesitter.install(languages)
        end, 1000)
      end

      vim.api.nvim_create_autocmd("FileType", {
        group = vim.api.nvim_create_augroup("noxflow_treesitter", { clear = true }),
        pattern = { "bash", "sh", "css", "dockerfile", "html", "javascript", "json", "jsonc", "lua", "markdown", "markdown.mdx", "rust", "toml", "tsx", "typescript", "typescriptreact", "yaml", "yaml.docker-compose", "yaml.gitlab", "yaml.helm-values" },
        callback = function(args)
          local language = vim.treesitter.language.get_lang(vim.bo[args.buf].filetype)
          if language and vim.treesitter.language.add(language) then
            vim.treesitter.start(args.buf, language)
          end
        end,
      })
    end,
  },
}
