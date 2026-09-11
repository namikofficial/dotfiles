# Non-interactive shell

Shell commands run non-interactively.

- Never invoke editors, pagers, interactive shells, or commands that wait for input.
- Prefer OpenCode file tools and command-specific non-interactive flags.
- Fail instead of prompting for credentials; never pipe passwords or blanket `yes`.
- Use managed process/tmux tools only for genuinely long-running commands.
