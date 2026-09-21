# Read-only workstation audit specification

`setup/audit-system.sh` is the first implementation of this contract. It
collects evidence and writes Markdown/JSON reports without running `sudo`,
changing services, changing filesystems, modifying credentials, or performing
a restore.

Every check reports `PASS`, `WARN`, `FAIL`, `N/A`, or `DEGRADED`. Missing tools
and unavailable privileges are capability results, not silent failures. The
collector must include timestamps, bounded output, exit status where relevant,
and redact secrets.

The report covers recovery/readiness, storage/filesystem, Biome crashes, Arch
package state, system and user services, timers, PSI/swap/resources, AI
configuration/session statistics, listeners/firewall/containers, and dirty
repository state. A real backup restore drill and any repair action remain
separate explicitly approved operations.
