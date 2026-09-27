# Non-interactive shell

Shell commands run non-interactively.

- Use focused repository scripts and command-specific non-interactive flags.
- Keep output bounded and preserve exit status; do not hide failed steps in command chains.
- Stop rather than prompt for credentials. Never pipe passwords or use blanket `yes`.
- Read state-changing scripts before running them and preserve user files before replacement.
- Use registered project tmux sessions only for genuinely long-running work.
