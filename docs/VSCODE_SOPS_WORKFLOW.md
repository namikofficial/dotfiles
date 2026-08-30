# Editing SOPS secrets in VS Code

The `signageos.signageos-vscode-sops` extension can decrypt supported SOPS files
in memory and re-encrypt them when they are saved. No `SOPS_AGE_KEY_FILE`
export or command-line flags are needed after the dotfiles setup is installed.
The managed settings associate `*.env.sops` with the `dotenv` language; without
that association VS Code opens the ciphertext as ordinary text and you will see
`ENC[...]` instead of the decrypted editor.

## One-time setup

From the dotfiles repository:

```bash
./setup/install-vscode-sops.sh
```

The installer installs both the SOPS and dotenv extensions. It preserves the existing VS Code user settings in a timestamped
backup and links VS Code to `code/vscode-user-settings.json`. The managed
settings point SOPS at the private age key in the private scripts submodule.

The age private key is never stored in this public dotfiles repository. Its
permissions are set to owner-readable only.

## Normal workflow

Open an encrypted environment file normally:

```bash
code /home/namik/Documents/code/noxorigin/workspace/infra/env/staging.env.sops
```

After installation, reload the VS Code window if it was already open. The
status bar should identify the file as `dotenv`. Edit `NOX_RESEND_API_KEY`, save
the file, and close it. VS Code shows the
decrypted dotenv contents while editing; the file on disk remains encrypted.
Repeat for `production.env.sops` when the production secret is also being
rotated.

If you still see `ENC[...]`, check that both extensions are installed and that
the file language is `dotenv`. Do not manually decrypt the file into the
workspace.

Validate without printing the secret:

```bash
cd /home/namik/Documents/code/noxorigin/workspace/infra
./scripts/validate-sops-env.sh
```

From any directory, the local shell helpers avoid path and key-file flags:

```zsh
nox-env-edit staging
nox-env-edit production
nox-billings-env-edit staging
nox-tickets-env-edit staging
nox-env-validate staging
nox-env-validate production
nox-help
```

The validator checks all encrypted deployment environments and reports only
file names and placeholder status; it does not print secret values.

Commit only the encrypted files:

```bash
git add env/staging.env.sops env/production.env.sops
git commit -m "fix(infra): rotate Resend deployment secret"
git push origin prod-sync
```

The deployment workflow decrypts the selected encrypted environment on the
server during deployment. Never create or commit a plaintext `.env` file.
