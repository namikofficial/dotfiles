# NoxFlow Configuration

Configuration is loaded by `noxd` and `noxctl config` from `$XDG_CONFIG_HOME/noxflow/`.

## File layout

```
~/.config/noxflow/
├── config.toml          # Base user configuration
├── config.local.toml    # Machine-local overrides (gitignored)
└── profiles/
    ├── laptop.toml      # Named profile example
    ├── docked.toml
    ├── focus.toml
    └── gaming.toml
```

## Loading order

Values from later files override earlier ones:

1. Code defaults (embedded in `noxflow-config`)
2. `config.toml`
3. Named profile chain (profile → `extends` → parent → …)
4. `config.local.toml` (highest TOML priority)
5. Runtime environment variables (paths only – see below)

## Profile selection

1. `--profile <name>` flag passed to `noxd` or `noxctl config`
2. `$NOXFLOW_PROFILE` environment variable
3. `profile` key in `config.toml`

If none of the above is set, no profile file is loaded.

## Profile inheritance

Profiles can extend another profile with an `extends` key:

```toml
# profiles/laptop.toml
extends = "base"

[power]
profile = "balanced"
```

```toml
# profiles/base.toml
[appearance]
density = "comfortable"
radius = 12
```

The chain is resolved depth-first, with child values overriding parent values.
Circular references are detected and reported as `CircularInheritance` errors
before startup.

## Machine-local overrides

Create `config.local.toml` alongside `config.toml` for machine-specific
changes that should not be committed to version control:

```toml
# config.local.toml
[network]
wifi_backend = "iwd"

[appearance]
density = "compact"
```

This file is loaded **after** the profile chain, so it overrides everything
in `config.toml` and the active profile.

## Environment variable overrides

The following environment variables override runtime paths only.
They are never read from TOML files:

| Variable              | Default                    | Purpose                |
|-----------------------|----------------------------|------------------------|
| `NOXFLOW_CONFIG_DIR`  | `$XDG_CONFIG_HOME/noxflow` | Config file directory  |
| `NOXFLOW_PROFILE`     | (none)                     | Active profile name    |
| `XDG_CONFIG_HOME`     | `$HOME/.config`            | XDG config base        |
| `XDG_RUNTIME_DIR`     | `/tmp`                     | Runtime socket root    |
| `XDG_STATE_HOME`      | `$HOME/.local/state`       | State data directory   |
| `XDG_CACHE_HOME`      | `$HOME/.cache`             | Cache directory        |

## Configuration sections

Every section has typed defaults embedded in the `noxflow-config` crate.
The full schema with field types and constraints is in
`core/noxflow-config/src/config.rs`.

| Section       | Key fields                        | Constraints                               |
|---------------|-----------------------------------|-------------------------------------------|
| `appearance`  | profile, density, radius, mode    | radius: 0–36, density/mode: enum          |
| `shell`       | name, fallback, reduced_motion    | name and fallback must be non-empty       |
| `providers`   | audio..clipboard booleans         | all default to true                       |
| `audio`       | `max_volume`                       | volume clamp, default 100                 |
| `brightness`  | `minimum`, `step`, `external_backend` | minimum 0–100, step 1–100, backend `none` or `ddcutil` |
| `notifications`| timeout, max_history, dnd        | timeout: 1–3600                           |
| `power`       | profile, dim..suspend             | profile: performance/balanced/power-saver |
| `network`     | wifi_backend, dns                 |                                            |
| `media`       | mpris, osd, default player, artwork cache | remote artwork caching is disabled by default; enabled cache defaults to 50 MiB and 7 days |
| `developer`   | editor, terminal, project_path    |                                            |
| `ai`          | provider, endpoint, temperature   | temperature: 0.0–2.0, max_tokens: 1–128000|
| `fallback`    | shell, compositor, launcher       | all non-empty                              |

## Validation errors

All validation errors include the exact field path, e.g.:

```
validation error at `appearance.radius`: value 99 out of range 0–36
validation error at `schema_version`: expected version 1, got 99
```

Multiple errors are accumulated and reported together before the daemon
starts or the config command exits.

## Redacted output

Sensitive fields (ending in `_key`, `_token`, `_secret`, `_password`,
or named `api_key`) are replaced with `"__REDACTED__"` in `noxctl config`
output. The actual values are never written to stdout.

## Config display

```sh
noxctl config
```

Prints the resolved configuration as pretty-printed JSON with secrets
redacted and runtime paths included. Exit code is 0 on success, 1 on
validation errors.

## Example

See `config/default.toml` for a complete annotated example.
