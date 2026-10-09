# Editing SOPS secrets in VS Code

The `signageos.signageos-vscode-sops` extension decrypts SOPS files in memory
when they are opened and re-encrypts them on save. The file on disk always
stays encrypted.

Three settings in `code/vscode-user-settings.json` make this work, and
`setup/check-stale-references.sh` fails if any of them is removed:

- `sops.enabled` and `sops.binPath`: turn the extension on.
- `sops.defaults.ageKeyFile`: the private age key in the private scripts
  submodule. VS Code is usually launched from the desktop, so it never sees a
  shell `SOPS_AGE_KEY_FILE`.
- `files.associations` `"*.env.sops": "dotenv"`: `.env.sops` is not a format
  sops recognises. Without this, the file opens as ciphertext (`ENC[...]`).

## One-time setup

```bash
./setup/install-vscode-sops.sh
```

This links VS Code to `code/vscode-user-settings.json` (backing up any
existing file) and installs the SOPS and dotenv extensions. Reload any open
VS Code window afterwards.

## Encrypted files in the noxorigin repo

`~/Documents/code/noxorigin/noxorigin` (rules in its `.sops.yaml`):

| Name              | Path                                     |
| ----------------- | ---------------------------------------- |
| `staging`         | `deploy/env/staging.env.sops`            |
| `production`      | `deploy/env/production.env.sops`         |
| `redis`           | `deploy/env/redis.env.sops`              |
| `android-signing` | `deploy/secrets/android-signing.env.sops` |

## Shell helpers

Defined in `aliases.local.zsh`. They work from any directory.

```zsh
nox-env-edit staging        # open in VS Code, decrypted
nox-env-sops production     # edit with `sops edit` in $EDITOR instead
nox-env-validate            # runs `just secrets-check`; prints no values
```

`aliases.local.zsh` also exports `SOPS_AGE_KEY_FILE` for interactive shells,
so plain `sops` works too. Because of the `.env.sops` suffix, pass the type
explicitly:

```bash
sops edit --input-type dotenv --output-type dotenv deploy/env/staging.env.sops
```

## Troubleshooting

If a file still shows `ENC[...]`:

1. The status bar language should say `dotenv`. If it doesn't, the file
   association is missing.
2. `code --list-extensions` should list both `signageos.signageos-vscode-sops`
   and `mikestead.dotenv`.
3. Run `nox-env-validate`. If the CLI can't decrypt either, the problem is the
   key or the recipients, not VS Code.

Never write a decrypted copy into the repository. Commit only `*.env.sops`.
