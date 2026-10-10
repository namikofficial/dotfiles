-- Open *.env.sops files decrypted and re-encrypt them on save, like the VS
-- Code SOPS extension. The file on disk is always ciphertext.
--
-- Safety rules (each one was a reproduced leak or data-loss path):
--   * The decrypted buffer never touches disk: no swap, undo or backup file,
--     and shada is disabled for the rest of the session once a secret has
--     been decrypted (registers and history would otherwise persist it).
--   * Writes are handled only by a buffer-local BufWriteCmd. Writing to any
--     other path (:w other.env, :saveas) is refused, so plaintext cannot be
--     written out by accident.
--   * The "decrypted" flag is cleared at the start of every read. A failed
--     re-read (e.g. after git pull) leaves an empty read-only buffer that can
--     never be saved, so it cannot overwrite the real ciphertext.
--   * Saves are atomic: encrypt in memory, write a temp file next to the
--     target, check every step, then rename over it.
--
-- Encryption runs in the file's directory with --filename-override, so sops
-- finds the repo's .sops.yaml and applies its creation rules (recipients).
-- New encrypted files are created with the sops CLI, not here.
local M = {}

local default_key = vim.fn.expand("~/Documents/code/dotfiles/private/scripts/noxorigin/sops/age/keys.txt")

local function sops_env()
  local env = {}
  if (vim.env.SOPS_AGE_KEY_FILE or "") == "" and vim.fn.filereadable(default_key) == 1 then
    env.SOPS_AGE_KEY_FILE = default_key
  end
  return env
end

local function run(args, opts)
  if vim.fn.executable("sops") ~= 1 then
    return nil, "sops is not installed"
  end
  local result = vim.system(args, vim.tbl_extend("force", { text = true, env = sops_env() }, opts or {})):wait()
  if result.code ~= 0 then
    return nil, vim.trim(result.stderr ~= "" and result.stderr or ("sops exited " .. result.code))
  end
  return result.stdout
end

local function real(path)
  return vim.uv.fs_realpath(path) or vim.fn.fnamemodify(path, ":p")
end

local function protect(buf)
  vim.bo[buf].swapfile = false
  vim.bo[buf].undofile = false
  vim.api.nvim_buf_call(buf, function()
    vim.opt_local.backup = false
    vim.opt_local.writebackup = false
  end)
end

local shada_disabled = false
local function disable_shada()
  if shada_disabled then
    return
  end
  shada_disabled = true
  vim.o.shadafile = "NONE"
  vim.notify("SOPS: history/registers will not be saved this session (shada off)", vim.log.levels.WARN)
end

-- Atomic replace: temp file in the same directory, every step checked.
local function atomic_write(target, data)
  local stat = vim.uv.fs_stat(target)
  local tmp = target .. ".nvim-sops-" .. vim.uv.getpid()
  local fd, err = vim.uv.fs_open(tmp, "w", stat and stat.mode or 420)
  if not fd then
    return false, err
  end
  local ok, werr = vim.uv.fs_write(fd, data)
  local synced = ok and vim.uv.fs_fsync(fd)
  vim.uv.fs_close(fd)
  if not ok or not synced then
    vim.uv.fs_unlink(tmp)
    return false, werr or "fsync failed"
  end
  local renamed, rerr = vim.uv.fs_rename(tmp, target)
  if not renamed then
    vim.uv.fs_unlink(tmp)
    return false, rerr
  end
  return true
end

function M.write(buf, source)
  if vim.b[buf].sops_decrypted ~= source then
    vim.notify("SOPS: refusing to save, this buffer was not decrypted from " .. source, vim.log.levels.ERROR)
    return
  end
  local text = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n") .. "\n"
  -- vim.system feeds stdin through a socket, and sops cannot open
  -- /dev/stdin on a socket (ENXIO). `cat |` gives it a real pipe; the
  -- plaintext still only exists in memory and pipes, never in a temp file.
  local cipher, err = run({
    "sh", "-c",
    'cat | exec sops encrypt --input-type dotenv --output-type dotenv --filename-override "$1" /dev/stdin',
    "sh", source,
  }, { stdin = text, cwd = vim.fn.fnamemodify(source, ":h") })
  if not cipher or not cipher:find("ENC%[") then
    vim.notify("SOPS: encryption failed, nothing written\n" .. (err or "output was not encrypted"), vim.log.levels.ERROR)
    return
  end
  local ok, werr = atomic_write(source, cipher)
  if not ok then
    vim.notify("SOPS: write failed, the original file is unchanged\n" .. tostring(werr), vim.log.levels.ERROR)
    return
  end
  vim.bo[buf].modified = false
  vim.notify("SOPS: encrypted and saved " .. vim.fn.fnamemodify(source, ":~:."), vim.log.levels.INFO)
end

local function guard_writes(buf, source)
  local group = vim.api.nvim_create_augroup("noxflow_sops_buf_" .. buf, { clear = true })
  vim.api.nvim_create_autocmd({ "BufWriteCmd", "FileWriteCmd", "FileAppendCmd" }, {
    group = group,
    buffer = buf,
    callback = function(args)
      if args.event == "BufWriteCmd" and real(args.match) == source then
        M.write(buf, source)
      else
        vim.notify("SOPS: refusing to write decrypted content anywhere but its encrypted source", vim.log.levels.ERROR)
      end
    end,
  })
end

function M.read(args)
  local buf = args.buf
  local source = real(args.match)
  vim.b[buf].sops_decrypted = nil -- never trust a flag from a previous read
  protect(buf)
  guard_writes(buf, source) -- installed before decrypting: a failed read is unsaveable too
  local plain, err = run({ "sops", "decrypt", "--input-type", "dotenv", "--output-type", "dotenv", source })
  if not plain then
    vim.bo[buf].modifiable = true
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, {})
    vim.bo[buf].modifiable = false
    vim.bo[buf].readonly = true
    vim.notify("SOPS: could not decrypt " .. vim.fn.fnamemodify(source, ":~:.") .. "\n" .. err, vim.log.levels.ERROR)
    return
  end
  disable_shada()
  local lines = vim.split(plain, "\n", { plain = true })
  if lines[#lines] == "" then
    table.remove(lines)
  end
  vim.bo[buf].modifiable = true
  vim.bo[buf].readonly = false
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modified = false
  vim.bo[buf].filetype = "sh"
  vim.b[buf].sops_decrypted = source
  vim.notify("SOPS: decrypted in memory; saving re-encrypts", vim.log.levels.INFO)
end

vim.api.nvim_create_autocmd("BufReadCmd", {
  group = vim.api.nvim_create_augroup("noxflow_sops", { clear = true }),
  pattern = "*.env.sops",
  callback = M.read,
})

return M
