# NoxOrigin workstation profile

NoxOrigin keeps repository workflows in its root `justfile`. This dotfiles
profile only provides workstation wiring; it never stores database passwords,
Resend keys, SOPS plaintext, or SSH private keys.

The repository is expected at:

```text
/home/namik/Documents/code/noxorigin/noxorigin
```

Install the profile with:

```bash
./setup/install-noxorigin-profile.sh
```

The installer creates `~/.config/noxorigin/repo-root` as a symlink and probes
both server aliases.

## SSH configuration is managed

`~/.ssh/config` is owned by this repository as [`ssh/config`](../../ssh/config).
Install it with:

```bash
./setup/install-ssh-config.sh          # backs up the current file, then links
./setup/install-ssh-config.sh --dry-run
./setup/install-ssh-config.sh --restore
```

`ssh/config` is also installed by `./setup/bootstrap.sh` on every run; pass
`--no-ssh-config` to skip it. Editing `~/.ssh/config` directly is not meaningful,
because it is a symlink — edit `ssh/config` instead.

| Alias | Target | Use |
| --- | --- | --- |
| `nox` | `server.noxorigin.com` | the current server |
| `nox-tunnel` | `server.noxorigin.com` | local PostgreSQL/Redis forwards for development |
| `noxorigin` | `31.97.202.202` | the previous server, kept as the migration rollback path |
| `noxorigin-tunnel` | `31.97.202.202` | the previous server's development forwards |

`noxorigin` and `noxorigin-tunnel` are deliberately retained. While both hosts are
live they are the way back, and removing them is a separate decision made after
the new server has served real traffic. Keep them as distinct host entries even
though they share an address, so retiring one is a one-line edit.

The deployment tooling reads `NOXORIGIN_SSH_ALIAS` and defaults to `noxorigin`.
To deploy to the current server, export `NOXORIGIN_SSH_ALIAS=nox`.

Use `just doctor`, `just check`, and `just verify` from the repository, and
`just vps-check` / `just vps-provision` to converge a server. Keep the real
local/staging values in the repository's ignored `.env` and keep production
values encrypted under `deploy/env/production.env.sops`.

Provisioning, the Caddy setup and customer domains are documented in
`noxorigin/docs/VPS_MIGRATION_PLAN.md`.