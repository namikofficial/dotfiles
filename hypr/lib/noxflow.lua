local M = {}

function M.include(path)
  local probe = io.open(path, "r")
  if not probe then
    return
  end
  probe:close()

  local chunk, err = loadfile(path)
  if not chunk then
    error(err)
  end

  local ok, run_err = pcall(chunk)
  if not ok then
    error(run_err)
  end
end

function M.bind(keys, dispatcher, opts)
  hl.bind(keys, dispatcher, opts or {})
end

function M.exec(keys, command, opts)
  M.bind(keys, hl.dsp.exec_cmd(command), opts)
end

function M.workspace(keys, target, opts)
  M.bind(keys, hl.dsp.focus({ workspace = target }), opts)
end

function M.move_workspace(keys, target, opts)
  M.bind(keys, hl.dsp.window.move({ workspace = target, follow = false }), opts)
end

function M.rule(spec)
  hl.window_rule(spec)
end

function M.dispatch_all(dispatchers)
  return function()
    for _, dispatcher in ipairs(dispatchers) do
      hl.dispatch(dispatcher)
    end
  end
end

return M
