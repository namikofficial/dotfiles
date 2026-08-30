local utils = require("noxflow.utils")

local function project_config_root(ctx, markers)
  local root = utils.find_root(ctx.filename, markers)
  return root or utils.buf_root(ctx.bufnr)
end

local node_tools = vim.fn.stdpath("config") .. "/tools/node_modules/.bin/"

return {
  {
    "neovim/nvim-lspconfig",
    event = { "BufReadPre", "BufNewFile" },
    dependencies = {
      "saghen/blink.cmp",
      "mrcjkb/rustaceanvim",
    },
    config = function()
      local capabilities = require("blink.cmp").get_lsp_capabilities()

      vim.lsp.config("*", {
        capabilities = capabilities,
        flags = {
          debounce_text_changes = 150,
        },
      })

      local servers = {
        bashls = {},
        cssls = {
          cmd = { node_tools .. "vscode-css-language-server", "--stdio" },
          init_options = { provideFormatter = false },
        },
        dockerls = {},
        eslint = {
          cmd = { node_tools .. "vscode-eslint-language-server", "--stdio" },
          settings = {
            format = false,
            workingDirectory = { mode = "auto" },
          },
        },
        html = {
          cmd = { node_tools .. "vscode-html-language-server", "--stdio" },
          init_options = {
            provideFormatter = false,
            configurationSection = { "html", "css", "javascript" },
            embeddedLanguages = { css = true, javascript = true },
          },
        },
        jsonls = {
          cmd = { node_tools .. "vscode-json-language-server", "--stdio" },
          init_options = { provideFormatter = false },
        },
        lua_ls = {
          settings = {
            Lua = {
              diagnostics = { globals = { "vim" } },
              workspace = { checkThirdParty = false },
              telemetry = { enable = false },
            },
          },
        },
        marksman = {},
        ts_ls = {
          cmd = { node_tools .. "typescript-language-server", "--stdio" },
          settings = {
            typescript = {
              inlayHints = {
                includeInlayParameterNameHints = "all",
                includeInlayParameterNameHintsWhenArgumentMatchesName = false,
                includeInlayFunctionParameterTypeHints = true,
                includeInlayVariableTypeHints = false,
                includeInlayPropertyDeclarationTypeHints = true,
                includeInlayFunctionLikeReturnTypeHints = true,
                includeInlayEnumMemberValueHints = true,
              },
            },
            javascript = {
              inlayHints = {
                includeInlayParameterNameHints = "all",
                includeInlayParameterNameHintsWhenArgumentMatchesName = false,
                includeInlayFunctionParameterTypeHints = true,
                includeInlayVariableTypeHints = false,
                includeInlayPropertyDeclarationTypeHints = true,
                includeInlayFunctionLikeReturnTypeHints = true,
                includeInlayEnumMemberValueHints = true,
              },
            },
          },
        },
        yamlls = {
          settings = {
            yaml = {
              keyOrdering = false,
              format = { enable = false },
            },
          },
        },
      }

      servers.eslint.root_dir = function(bufnr, on_dir)
        local filename = vim.api.nvim_buf_get_name(bufnr)
        local root = project_config_root({ filename = filename, bufnr = bufnr }, {
          "eslint.config.js",
          "eslint.config.mjs",
          "eslint.config.cjs",
          ".eslintrc",
          ".eslintrc.js",
          ".eslintrc.json",
          "package.json",
        })
        if root then
          on_dir(root)
        end
      end

      local binaries = {
        bashls = "bash-language-server",
        cssls = node_tools .. "vscode-css-language-server",
        dockerls = "docker-langserver",
        eslint = node_tools .. "vscode-eslint-language-server",
        html = node_tools .. "vscode-html-language-server",
        jsonls = node_tools .. "vscode-json-language-server",
        lua_ls = "lua-language-server",
        marksman = "marksman",
        ts_ls = node_tools .. "typescript-language-server",
        yamlls = "yaml-language-server",
      }

      for name, config in pairs(servers) do
        if vim.fn.executable(binaries[name]) == 1 then
          vim.lsp.config(name, config)
          vim.lsp.enable(name)
        end
      end
    end,
  },
  {
    "mrcjkb/rustaceanvim",
    version = "^6",
    lazy = false,
    init = function()
      vim.g.rustaceanvim = {
        server = {
          default_settings = {
            ["rust-analyzer"] = {
              cargo = { allFeatures = true },
              check = { command = "clippy" },
            },
          },
        },
      }
    end,
  },
  {
    "saecki/crates.nvim",
    ft = "toml",
    event = "BufRead Cargo.toml",
    dependencies = { "nvim-lua/plenary.nvim" },
    opts = {},
  },
  {
    "stevearc/conform.nvim",
    event = { "BufWritePre", "BufReadPre" },
    opts = function()
      local web_markers = {
        ".prettierrc",
        ".prettierrc.json",
        ".prettierrc.js",
        ".prettierrc.cjs",
        ".prettierrc.yaml",
        "prettier.config.js",
        "prettier.config.cjs",
      }
      local function root_with_markers(filename, markers)
        return utils.find_root(filename, markers)
      end

      local function project_has_prettier(filename)
        local root = root_with_markers(filename, web_markers)
        if root then
          return true
        end
        local package = utils.find_root(filename, { "package.json" })
        if not package then
          return false
        end

        if vim.fn.executable(package .. "/node_modules/.bin/prettier") == 1
          or vim.fn.executable(package .. "/node_modules/.bin/prettierd") == 1 then
          return true
        end

        local package_file = package .. "/package.json"
        if vim.fn.filereadable(package_file) ~= 1 then
          return false
        end
        local ok, package_json = pcall(vim.json.decode, table.concat(vim.fn.readfile(package_file), "\n"))
        if not ok or type(package_json) ~= "table" then
          return false
        end
        for _, field in ipairs({ "dependencies", "devDependencies", "peerDependencies", "optionalDependencies" }) do
          if type(package_json[field]) == "table" and (package_json[field].prettier or package_json[field].prettierd) then
            return true
          end
        end
        return false
      end

      local formatters_by_ft = {
        javascript = { "prettier", stop_after_first = true },
        javascriptreact = { "prettier", stop_after_first = true },
        json = { "prettier", stop_after_first = true },
        jsonc = { "prettier", stop_after_first = true },
        markdown = { "prettier", stop_after_first = true },
        rust = { "rustfmt" },
        sh = { "shfmt" },
        bash = { "shfmt" },
        toml = { "taplo" },
        tsx = { "prettier", stop_after_first = true },
        typescript = { "prettier", stop_after_first = true },
        typescriptreact = { "prettier", stop_after_first = true },
        yaml = { "prettier", stop_after_first = true },
      }

      return {
        notify_on_error = true,
        formatters_by_ft = formatters_by_ft,
        formatters = {
          prettier = {
            cwd = function(_, ctx)
              local markers = vim.deepcopy(web_markers)
              table.insert(markers, "package.json")
              return root_with_markers(ctx.filename, markers)
            end,
          },
        },
        format_on_save = function(bufnr)
          local filename = vim.api.nvim_buf_get_name(bufnr)
          local ft = vim.bo[bufnr].filetype
          local safe = vim.tbl_contains({ "rust", "sh", "bash", "toml" }, ft)
            or (vim.tbl_contains({ "javascript", "javascriptreact", "json", "jsonc", "markdown", "tsx", "typescript", "typescriptreact", "yaml" }, ft)
              and project_has_prettier(filename))
          if not safe then
            return
          end
          return { timeout_ms = 1000, lsp_format = "never" }
        end,
      }
    end,
    keys = {
      { "<leader>cf", function() require("conform").format({ async = true, lsp_format = "never" }) end, mode = { "n", "v" }, desc = "Format buffer" },
    },
  },
  {
    "mfussenegger/nvim-lint",
    event = { "BufWritePost", "InsertLeave" },
    config = function()
      local lint = require("lint")
      lint.linters_by_ft = {
        sh = { "shellcheck" },
        bash = { "shellcheck" },
      }

      if vim.fn.executable("markdownlint-cli2") == 1 then
        lint.linters_by_ft.markdown = { "markdownlint-cli2" }
      end

      vim.api.nvim_create_autocmd({ "BufWritePost", "InsertLeave" }, {
        group = vim.api.nvim_create_augroup("noxflow_lint", { clear = true }),
        callback = function(args)
          if lint.linters_by_ft[vim.bo[args.buf].filetype] then
            lint.try_lint(nil, { bufnr = args.buf })
          end
        end,
      })
    end,
  },
}
