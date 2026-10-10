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

      -- Biome lives in each project's node_modules (e.g. noxorigin), not on
      -- PATH, so only attach where a biome config and local binary exist.
      local biome_markers = { "biome.json", "biome.jsonc" }
      servers.biome = {
        root_dir = function(bufnr, on_dir)
          local root = utils.find_root(vim.api.nvim_buf_get_name(bufnr), biome_markers)
          if root and vim.fn.executable(root .. "/node_modules/.bin/biome") == 1 then
            on_dir(root)
          end
        end,
        cmd = function(dispatchers, config)
          local bin = config.root_dir .. "/node_modules/.bin/biome"
          return vim.lsp.rpc.start({ bin, "lsp-proxy" }, dispatchers, { cwd = config.root_dir })
        end,
      }
      servers.qmlls = { cmd = { "/usr/lib/qt6/bin/qmlls", "-E" } }

      local binaries = {
        biome = "node", -- resolved per project in root_dir above
        qmlls = "/usr/lib/qt6/bin/qmlls",
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

      vim.diagnostic.config({
        severity_sort = true,
        underline = true,
        update_in_insert = false,
        virtual_text = { spacing = 2, source = "if_many", prefix = "●" },
        float = { border = "rounded", source = "if_many" },
        signs = {
          text = {
            [vim.diagnostic.severity.ERROR] = "",
            [vim.diagnostic.severity.WARN] = "",
            [vim.diagnostic.severity.INFO] = "",
            [vim.diagnostic.severity.HINT] = "󰌵",
          },
        },
      })

      -- Buffer-local LSP keys. Neovim 0.12 already provides grn/gra/grr/gri/
      -- grt, K and [d/]d; these add the <leader>c "code" group on top.
      vim.api.nvim_create_autocmd("LspAttach", {
        group = vim.api.nvim_create_augroup("noxflow_lsp_attach", { clear = true }),
        callback = function(args)
          local client = vim.lsp.get_client_by_id(args.data.client_id)
          local function map(lhs, rhs, desc, mode)
            vim.keymap.set(mode or "n", lhs, rhs, { buffer = args.buf, desc = desc })
          end
          map("<leader>ca", vim.lsp.buf.code_action, "Code action", { "n", "v" })
          map("<leader>cr", vim.lsp.buf.rename, "Rename symbol")
          map("<leader>cd", vim.diagnostic.open_float, "Line diagnostics")
          map("<leader>cl", "<cmd>checkhealth vim.lsp<cr>", "LSP info")
          map("gD", vim.lsp.buf.declaration, "Go to declaration")
          if client and client:supports_method("textDocument/inlayHint") then
            map("<leader>ci", function()
              local on = vim.lsp.inlay_hint.is_enabled({ bufnr = args.buf })
              vim.lsp.inlay_hint.enable(not on, { bufnr = args.buf })
            end, "Toggle inlay hints")
          end
        end,
      })
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

      -- Biome projects (noxorigin) format with their pinned local biome;
      -- everything else keeps prettier.
      local function project_has_biome(filename)
        local root = utils.find_root(filename, { "biome.json", "biome.jsonc" })
        return root ~= nil and vim.fn.executable(root .. "/node_modules/.bin/biome") == 1
      end
      local function web(bufnr)
        if project_has_biome(vim.api.nvim_buf_get_name(bufnr)) then
          return { "biome" }
        end
        return { "prettier", stop_after_first = true }
      end
      local biome_fts = { "javascript", "javascriptreact", "json", "jsonc", "tsx", "typescript", "typescriptreact" }

      local formatters_by_ft = {
        javascript = web,
        javascriptreact = web,
        json = web,
        jsonc = web,
        markdown = { "prettier", stop_after_first = true },
        rust = { "rustfmt" },
        sh = { "shfmt" },
        bash = { "shfmt" },
        toml = { "taplo" },
        tsx = web,
        typescript = web,
        typescriptreact = web,
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
            or (vim.tbl_contains(biome_fts, ft) and project_has_biome(filename))
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
