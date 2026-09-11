# Rust workspace guidance

The Rust workspace contains `core/noxd`, `core/noxflow-ipc`,
`core/noxflow-config`, `core/noxflow-state`, `core/noxflow-diagnostics`, and
the `cli/noxctl` binary. Preserve the versioned IPC contract and existing
external behavior; do not invent compatibility layers without a caller.

Run the focused checks first, then the workspace gates when the change spans
packages:

```sh
cargo check --workspace
cargo test --workspace
```

Relevant integration tests include `core/noxd/tests/server.rs` and
`cli/noxctl/tests/cli.rs`. Keep `Cargo.lock` reproducible and inspect the full
diff before reporting completion.
