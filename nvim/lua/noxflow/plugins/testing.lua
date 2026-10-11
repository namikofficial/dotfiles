-- Testing and debugging.
--
-- Tests (neotest): adapters for the runners these projects actually use,
-- vitest and Playwright (noxorigin, trackMe) and cargo via rustaceanvim.
-- Keys live under <leader>T; results show inline next to each test.
--
-- Debugging (nvim-dap + dap-ui): VS Code's F-keys. Rust and C/C++ use the
-- installed lldb-dap (rustaceanvim wires Rust automatically). JavaScript
-- debugging needs vscode-js-debug, which is not installed, so it is not
-- configured rather than configured broken.
return {
  {
    "nvim-neotest/neotest",
    dependencies = {
      "nvim-neotest/nvim-nio",
      "nvim-lua/plenary.nvim",
      "marilari88/neotest-vitest",
      "thenbe/neotest-playwright",
      "mrcjkb/rustaceanvim",
    },
    keys = {
      { "<leader>Tt", function() require("neotest").run.run() end, desc = "Run nearest test" },
      { "<leader>Tf", function() require("neotest").run.run(vim.fn.expand("%")) end, desc = "Run tests in file" },
      { "<leader>Ta", function() require("neotest").run.run(vim.uv.cwd()) end, desc = "Run all tests (project)" },
      { "<leader>Tl", function() require("neotest").run.run_last() end, desc = "Re-run last test" },
      { "<leader>Td", function() require("neotest").run.run({ strategy = "dap" }) end, desc = "Debug nearest test" },
      { "<leader>Ts", function() require("neotest").summary.toggle() end, desc = "Test tree" },
      { "<leader>To", function() require("neotest").output.open({ enter = true, auto_close = true }) end, desc = "Test output" },
      { "<leader>TO", function() require("neotest").output_panel.toggle() end, desc = "Output panel" },
      { "<leader>Tx", function() require("neotest").run.stop() end, desc = "Stop tests" },
      { "<leader>Tw", function() require("neotest").watch.toggle(vim.fn.expand("%")) end, desc = "Watch file" },
      { "]t", function() require("neotest").jump.next({ status = "failed" }) end, desc = "Next failed test" },
      { "[t", function() require("neotest").jump.prev({ status = "failed" }) end, desc = "Previous failed test" },
    },
    config = function()
      require("neotest").setup({
        adapters = {
          require("neotest-vitest"),
          require("neotest-playwright").adapter({
            options = { persist_project_selection = true, enable_dynamic_test_discovery = true },
          }),
          require("rustaceanvim.neotest"),
        },
        status = { virtual_text = true },
        output = { open_on_run = false },
        quickfix = { open = false },
      })
    end,
  },
  {
    "mfussenegger/nvim-dap",
    dependencies = {
      { "rcarriga/nvim-dap-ui", dependencies = { "nvim-neotest/nvim-nio" } },
      "theHamsta/nvim-dap-virtual-text",
    },
    keys = {
      { "<F5>", function() require("dap").continue() end, desc = "Debug: start / continue" },
      { "<S-F5>", function() require("dap").terminate() end, desc = "Debug: stop" },
      { "<F9>", function() require("dap").toggle_breakpoint() end, desc = "Debug: toggle breakpoint" },
      { "<F10>", function() require("dap").step_over() end, desc = "Debug: step over" },
      { "<F11>", function() require("dap").step_into() end, desc = "Debug: step into" },
      { "<S-F11>", function() require("dap").step_out() end, desc = "Debug: step out" },
      { "<leader>db", function() require("dap").toggle_breakpoint() end, desc = "Toggle breakpoint" },
      { "<leader>dB", function() require("dap").set_breakpoint(vim.fn.input("Condition: ")) end, desc = "Conditional breakpoint" },
      { "<leader>dc", function() require("dap").continue() end, desc = "Start / continue" },
      { "<leader>dr", function() require("dap").repl.toggle() end, desc = "Debug console" },
      { "<leader>du", function() require("dapui").toggle() end, desc = "Debug panels" },
      { "<leader>dt", function() require("dap").terminate() end, desc = "Stop debugging" },
      { "<leader>de", function() require("dapui").eval() end, mode = { "n", "v" }, desc = "Evaluate expression" },
    },
    config = function()
      local dap, dapui = require("dap"), require("dapui")
      dapui.setup()
      require("nvim-dap-virtual-text").setup({})
      -- Open the panels when a session starts and close them when it ends,
      -- like VS Code's debug view.
      dap.listeners.after.event_initialized["noxflow_dapui"] = function() dapui.open() end
      dap.listeners.before.event_terminated["noxflow_dapui"] = function() dapui.close() end
      dap.listeners.before.event_exited["noxflow_dapui"] = function() dapui.close() end

      vim.fn.sign_define("DapBreakpoint", { text = "●", texthl = "DiagnosticError" })
      vim.fn.sign_define("DapBreakpointCondition", { text = "◆", texthl = "DiagnosticWarn" })
      vim.fn.sign_define("DapStopped", { text = "▶", texthl = "DiagnosticOk", linehl = "Visual" })

      -- C / C++ through lldb-dap (Rust is configured by rustaceanvim).
      if vim.fn.executable("lldb-dap") == 1 then
        dap.adapters.lldb = { type = "executable", command = "lldb-dap", name = "lldb" }
        local launch = {
          name = "Launch executable",
          type = "lldb",
          request = "launch",
          program = function() return vim.fn.input("Executable: ", vim.fn.getcwd() .. "/", "file") end,
          cwd = "${workspaceFolder}",
          stopOnEntry = false,
        }
        dap.configurations.c = { launch }
        dap.configurations.cpp = { launch }
      end
    end,
  },
}
