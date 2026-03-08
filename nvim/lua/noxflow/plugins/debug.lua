return {
  {
    "mfussenegger/nvim-dap",
    dependencies = {
      "jay-babu/mason-nvim-dap.nvim",
      "leoluz/nvim-dap-go",
      "mfussenegger/nvim-dap-python",
      "nvim-neotest/nvim-nio",
      "rcarriga/nvim-dap-ui",
      "theHamsta/nvim-dap-virtual-text",
      "williamboman/mason.nvim",
    },
    config = function()
      local dap = require("dap")
      local dapui = require("dapui")

      require("mason-nvim-dap").setup({
        ensure_installed = {
          "codelldb",
          "debugpy",
          "delve",
          "js-debug-adapter",
        },
        automatic_installation = true,
      })

      require("nvim-dap-virtual-text").setup({})
      dapui.setup({
        layouts = {
          {
            elements = {
              { id = "scopes", size = 0.5 },
              { id = "breakpoints", size = 0.2 },
              { id = "stacks", size = 0.15 },
              { id = "watches", size = 0.15 },
            },
            position = "left",
            size = 48,
          },
          {
            elements = {
              { id = "repl", size = 0.5 },
              { id = "console", size = 0.5 },
            },
            position = "bottom",
            size = 12,
          },
        },
      })

      dap.listeners.after.event_initialized["dapui_config"] = function()
        dapui.open({})
      end
      dap.listeners.before.event_terminated["dapui_config"] = function()
        dapui.close({})
      end
      dap.listeners.before.event_exited["dapui_config"] = function()
        dapui.close({})
      end

      local mason_path = vim.fn.stdpath("data") .. "/mason/packages"

      dap.adapters["pwa-node"] = {
        type = "server",
        host = "127.0.0.1",
        port = "${port}",
        executable = {
          command = vim.fn.stdpath("data") .. "/mason/bin/js-debug-adapter",
          args = { "${port}" },
        },
      }

      local js_languages = {
        "javascript",
        "javascriptreact",
        "typescript",
        "typescriptreact",
      }

      for _, language in ipairs(js_languages) do
        dap.configurations[language] = {
          {
            type = "pwa-node",
            request = "launch",
            name = "Launch current file",
            cwd = "${workspaceFolder}",
            program = "${file}",
            sourceMaps = true,
            console = "integratedTerminal",
          },
          {
            type = "pwa-node",
            request = "attach",
            name = "Attach to process",
            processId = require("dap.utils").pick_process,
            cwd = "${workspaceFolder}",
          },
        }
      end

      require("dap-python").setup(mason_path .. "/debugpy/venv/bin/python")
      require("dap-go").setup()

      dap.adapters.codelldb = {
        type = "server",
        port = "${port}",
        executable = {
          command = mason_path .. "/codelldb/extension/adapter/codelldb",
          args = { "--port", "${port}" },
        },
      }

      dap.configurations.rust = {
        {
          name = "Launch Rust target",
          type = "codelldb",
          request = "launch",
          cwd = "${workspaceFolder}",
          stopOnEntry = false,
          program = function()
            return vim.fn.input("Path to binary: ", vim.fn.getcwd() .. "/target/debug/", "file")
          end,
        },
      }
    end,
    keys = {
      { "<F5>", function() require("dap").continue() end, desc = "Debug continue" },
      { "<F9>", function() require("dap").toggle_breakpoint() end, desc = "Toggle breakpoint" },
      { "<F10>", function() require("dap").step_over() end, desc = "Debug step over" },
      { "<F11>", function() require("dap").step_into() end, desc = "Debug step into" },
      { "<leader>db", function() require("dap").toggle_breakpoint() end, desc = "Breakpoint toggle" },
      { "<leader>dc", function() require("dap").continue() end, desc = "Debug continue" },
      { "<leader>di", function() require("dap").step_into() end, desc = "Debug step into" },
      { "<leader>do", function() require("dap").step_over() end, desc = "Debug step over" },
      { "<leader>dO", function() require("dap").step_out() end, desc = "Debug step out" },
      { "<leader>dr", function() require("dap").repl.toggle() end, desc = "Debug REPL" },
      { "<leader>du", function() require("dapui").toggle({}) end, desc = "Debug UI" },
      { "<leader>dx", function() require("dap").terminate() end, desc = "Debug stop" },
    },
  },
}
