# Code Doctor

Code Doctor is a local, offline JavaScript/TypeScript health scanner. It uses
the TypeScript compiler and type checker to find deprecated symbols (including
dependency declarations), compiler diagnostics, unsafe suppressions and common
type escapes. `--full` also runs locally installed ESLint and Knip without
installing anything.

Run `code-doctor`, `code-doctor --full`, or `code-doctor --changed` from a
project. Reports are written to `.code-doctor/`.
