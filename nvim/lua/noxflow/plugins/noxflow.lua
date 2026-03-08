return {
  {
    "noxflow/project-local",
    dir = vim.fn.stdpath("config"),
    name = "noxflow-project-local",
    lazy = false,
    config = function()
      local utils = require("noxflow.utils")

      local function run_repo_cmd(script, opts)
        local root = utils.noxflow_root()
        if not root or not utils.is_noxflow_repo(root) then
          return
        end
        utils.open_terminal("pnpm " .. script, {
          cwd = root,
          label = "noxflow:" .. script,
        })
      end

      local function run_package_script(script)
        local pkg = utils.nearest_package()
        if not pkg or not pkg.name or not pkg.scripts[script] then
          vim.notify("No local package script `" .. script .. "` found", vim.log.levels.WARN)
          return
        end
        local root = utils.noxflow_root()
        utils.open_terminal("pnpm --filter " .. pkg.name .. " " .. script, {
          cwd = root,
          label = pkg.name .. ":" .. script,
        })
      end

      local function set_noxflow_keymaps(args)
        local path = vim.api.nvim_buf_get_name(args.buf)
        if path == "" or not utils.is_noxflow_repo(path) then
          return
        end

        local map = function(lhs, rhs, desc)
          vim.keymap.set("n", lhs, rhs, { buffer = args.buf, desc = desc })
        end

        map("<leader>na", function()
          local root = utils.noxflow_root(path)
          utils.telescope_find_in_dir("NoxFlow Apps", root .. "/apps")
        end, "NoxFlow apps")

        map("<leader>np", function()
          local root = utils.noxflow_root(path)
          utils.telescope_find_in_dir("NoxFlow Packages", root .. "/packages")
        end, "NoxFlow packages")

        map("<leader>nd", function()
          local root = utils.noxflow_root(path)
          utils.telescope_find_in_dir("NoxFlow Docs", root .. "/docs")
        end, "NoxFlow docs")

        map("<leader>ns", function()
          local root = utils.noxflow_root(path)
          utils.telescope_grep_in_dir("NoxFlow Search", root)
        end, "NoxFlow search")

        map("<leader>nt", function() run_repo_cmd("test") end, "NoxFlow test")
        map("<leader>nl", function() run_repo_cmd("lint") end, "NoxFlow lint")
        map("<leader>nc", function() run_repo_cmd("type-check") end, "NoxFlow type-check")
        map("<leader>nF", function() run_repo_cmd("format") end, "NoxFlow format")
        map("<leader>npt", function() run_package_script("test") end, "NoxFlow package test")
        map("<leader>npl", function() run_package_script("lint") end, "NoxFlow package lint")
        map("<leader>npc", function() run_package_script("type-check") end, "NoxFlow package type-check")
        map("<leader>npd", function() run_package_script("dev") end, "NoxFlow package dev")
      end

      local group = vim.api.nvim_create_augroup("noxflow_project_local", { clear = true })
      vim.api.nvim_create_autocmd({ "BufReadPost", "BufNewFile" }, {
        group = group,
        callback = set_noxflow_keymaps,
      })

      vim.api.nvim_create_user_command("NoxflowTest", function()
        run_repo_cmd("test")
      end, {})
      vim.api.nvim_create_user_command("NoxflowLint", function()
        run_repo_cmd("lint")
      end, {})
      vim.api.nvim_create_user_command("NoxflowTypecheck", function()
        run_repo_cmd("type-check")
      end, {})
      vim.api.nvim_create_user_command("NoxflowFormat", function()
        run_repo_cmd("format")
      end, {})
    end,
  },
}
