# NoxFlow data layout

NoxFlow follows the XDG separation between user configuration, persistent
state, rebuildable cache data, and session-only runtime data.

| Directory | Contents | Durability |
|---|---|---|
| `$XDG_CONFIG_HOME/noxflow/` (default `~/.config/noxflow/`) | `config.toml`, machine-local overrides, and named configuration profiles | User-managed configuration |
| `$XDG_STATE_HOME/noxflow/` (default `~/.local/state/noxflow/`) | `state.toml`: appearance, shell, DND, device/profile selections, provider health, crash counters, and fallback history | Survives restart |
| `$XDG_CACHE_HOME/noxflow/` (default `~/.cache/noxflow/`) | Rebuildable indexes, downloaded metadata, and other performance-only artifacts | Safe to delete |
| `$XDG_RUNTIME_DIR/noxflow/` | `noxd.sock` and other session-only IPC data | Removed or invalid after the session |

Persistent state is TOML, versioned, written through an atomic temporary-file
replacement, and kept private with a `0700` directory and `0600` file mode.
Malformed state is quarantined as a `.corrupt-*` sibling and replaced with
defaults. A failed write leaves the in-memory state marked unsynced and is
reported by the daemon; it is never presented as successfully saved.

State contains no secrets, logs, cache data, or runtime socket data. Logs are
written through the daemon's logging path and are not embedded in state files.
