# NoxFlow Neovim guide

Open this any time with `Space H`. `Space` is the **leader** key; press it and
wait half a second, and a menu (which-key) shows what you can press next. You
never need to memorise everything: menus and search are always one key away.

## The three keys that teach you the rest

| Keys | What it does |
| --- | --- |
| `Space` (wait) | Menu of every leader command, grouped |
| `Space ?` | Every key that works in the current buffer |
| `Space s k` | Search all keymaps by what they do ("rename", "comment", …) |

## Modes in one minute

- **Normal** (default): move and run commands. `Esc` always gets you back here.
- **Insert**: type text. Enter with `i` (before cursor), `a` (after), `o` (new line below).
- **Visual**: select. `v` characters, `V` lines, then act on the selection.
- Save: `Ctrl-s` (any mode) or `:w`. Quit a window: `Space q`. Quit everything: `Space Q`.

## Files (VS Code equivalents)

| VS Code | Here |
| --- | --- |
| Explorer sidebar | `Space e` |
| Ctrl-P quick open | `Ctrl-p` or `Space Space` (smart: recent + project) |
| Search in files (Ctrl-Shift-F) | `Space f g` |
| Recent files | `Space f r` |
| Switch tabs | `Shift-h` / `Shift-l` |
| Close tab | `Space b d` |
| Pin tab | `Space b p` |
| Toggle comment (Ctrl-/) | `Ctrl-/` |
| Move line (Alt-Up/Down) | `Alt-Up` / `Alt-Down` |
| Terminal | `Space t t` (split) or `Space t f` (floating) |
| Git panel | `Space g g` (lazygit) |

Hidden files (`.env`, `.sops.yaml`, `.github/`) and gitignored files show in
the explorer like VS Code (gitignored ones are dimmed). Inside the explorer or
any picker: `H` toggles hidden files, `I` toggles ignored files.

### Explorer keys (`Space e`)

| Key | Action |
| --- | --- |
| `Enter` / `l` | Open file / expand folder |
| `h` | Collapse folder |
| `a` | New file (end the name with `/` for a folder) |
| `r` | Rename |
| `d` | Delete (to trash) |
| `c` / `m` | Copy / move |
| `?` | Show all explorer keys |

## Code (needs a language server; the statusline shows which are attached)

| Keys | Action |
| --- | --- |
| `gd` | Go to definition |
| `grr` | Find references |
| `K` | Hover docs |
| `Space c a` | Code action (quick fix) |
| `Space c r` | Rename symbol |
| `Space c d` | Show the error on this line |
| `Space c f` | Format file (also happens on save where the project has a formatter) |
| `Space c i` | Toggle inline type hints |
| `[d` / `]d` | Previous / next problem |
| `Space x x` | All problems (like the Problems panel) |

Formatting on save uses the project's own tool: Biome in noxorigin, Prettier
where a project has it, rustfmt, shfmt, taplo.

## Encrypted env files (SOPS)

Open any `*.env.sops` normally (`Ctrl-p`, type the name). It opens
**decrypted in memory**; `Ctrl-s` re-encrypts it. Nothing decrypted is ever
written to disk (no swap/undo files for that buffer). If the key is missing
you get an error and an empty read-only buffer, never a corrupted file.
Writing a decrypted buffer anywhere else (`:w other.env`) is refused, and
once a secret is open, nvim stops saving history/registers for that session.
Create new encrypted files with the `sops` CLI.
From a shell: `nox-env-edit staging` (VS Code) or `nox-env-sops staging`.

## Moving around faster (learn these one at a time)

| Keys | Action |
| --- | --- |
| `w` / `b` | Next / previous word |
| `0` / `$` | Start / end of line |
| `gg` / `G` | Top / bottom of file |
| `Ctrl-d` / `Ctrl-u` | Half page down / up |
| `s` then 2 letters | Jump anywhere on screen (flash) |
| `/text` then `n` | Search, then next match |
| `ciw` | Change the word under the cursor |
| `u` / `Ctrl-r` | Undo / redo |
| `Ctrl-h/j/k/l` | Move between splits and tmux panes (in a terminal split, press `Ctrl-\` `Ctrl-n` first) |

## When something looks wrong

- `Space c l` — language server health for this file.
- `:Lazy` — plugin manager (update, see errors).
- `:checkhealth` — full diagnosis.
- `:messages` — recent errors and notifications.

Practice: run `:Tutor` once (30 minutes). It is the fastest way to make the
basic motions automatic.
