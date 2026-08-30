# Shell non-interactive strategy

This policy is vendored from the `opencode-shell-strategy` project so OpenCode
does not need to fetch instructions during startup.

OpenCode shell execution is non-interactive. Commands that wait for input,
launch a pager, or open an editor can hang until timeout.

## Rules

1. Do not use editors or pagers such as `vim`, `nano`, `less`, `more`, or `man`.
2. Do not use interactive modes such as `git add -p`, `git rebase -i`, or `bash -i`.
3. Prefer command-specific non-interactive flags such as `--no-pager`, `--no-edit`, `--no-input`, and `-y`.
4. Fail fast when credentials or user input are required; never pipe passwords or blanket `yes` into commands.
5. Prefer OpenCode read/write/edit tools instead of shell text manipulation.
6. Use `GIT_TERMINAL_PROMPT=0` for Git network commands that must fail instead of prompting.
7. Use `sudo -n` when a privileged status check is explicitly authorized; stop if it needs a password.
8. Use `git --no-pager diff` and `git --no-pager log`.
9. Use `git commit -m "message"` and `git merge --no-edit` when those actions are authorized.
10. Use tmux tools for long-running servers, watchers, logs, and test processes; do not background them from the shell.

The source policy is maintained at:
https://github.com/JRedeker/opencode-shell-strategy/blob/trunk/shell_strategy.md
