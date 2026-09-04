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

The installer creates `~/.config/noxorigin/repo-root` as a symlink and checks
the existing `ssh noxorigin` alias. SSH configuration remains user-owned in
`~/.ssh/config`; the installer will not overwrite it.

Use `just doctor`, `just check`, and `just verify` from the repository. Keep
the real local/staging values in the repository's ignored `.env` and keep
production values encrypted under `deploy/env/production.env.sops`.
