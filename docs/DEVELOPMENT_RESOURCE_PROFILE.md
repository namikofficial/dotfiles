# Development resource profile

This laptop profile keeps Android, Rust, VS Code, and browser-heavy sessions
responsive on a 16 GiB machine. It uses fast compressed swap before a large
NVMe fallback, stops optional development services from living in memory when
idle, and gives the Android emulator conservative defaults.

## Apply and verify

Review the exact actions first:

```sh
workstationctl resources plan
```

Apply the root-owned profile and reboot once so zram is recreated at 16 GiB:

```sh
sudo /home/namik/Documents/code/dotfiles/setup/workstationctl resources apply
systemctl reboot
```

After reboot:

```sh
/home/namik/Documents/code/dotfiles/setup/workstationctl resources verify
swapon --show
```

The expected layout is `/dev/zram0` at priority 100 and a 50 GiB
`/swap/swapfile` at priority 10. The swapfile is a Btrfs-safe swapfile in its
own subvolume. It is overload protection, not a hibernation configuration.

To restore the most recently backed-up system configuration:

```sh
sudo workstationctl resources rollback
systemctl reboot
```

## Android emulator modes

The default mode leaves memory and CPU available for Gradle, Metro, Chrome,
and VS Code:

```sh
android-dev.sh start
```

Use the faster mode when emulator responsiveness matters more than concurrent
build capacity:

```sh
android-dev.sh start-fast
```

Both modes retain KVM and host-GPU acceleration. The default uses 3 GiB and
two cores; fast mode uses 4 GiB and four cores. Audio, virtual cameras,
metrics, and boot animation are disabled.

For memory-heavy builds, prefer bounded workers instead of allowing Gradle or
Cargo to saturate every CPU and all available memory:

```sh
./gradlew --max-workers=2 assembleDebug
cargo build -j 8
```

## Optional services and local AI

Docker uses socket activation. The first Docker command starts the daemon. To
return its memory after development:

```sh
sudo systemctl stop docker.service docker.socket containerd.service
sudo systemctl start docker.socket
```

The local CUDA model router does not start at login. It is a user unit
(`llama-router.service`) managed by `setup/install-llama-router.sh` and started
on demand:

```sh
llama-router start     # render the preset and start the unit
llama-router status    # unit state, health and the available lanes
llama-router stop
```

The router is llama.cpp in router mode, serving the agentic-coding lanes
defined in `system/llama-router/models.ini.template`. Two properties of it are
load-bearing on this hardware and must not be changed casually:

- It runs with `--models-max 1`. The llama.cpp default keeps four models
  resident, which is an immediate `cudaMalloc` OOM on the 6 GB card and turns
  every request into an HTTP 500.
- Context sizes are pinned per lane and were measured, not estimated. A lane
  that does not fit its measured ceiling must not be widened.

`setup/test-local-models.sh` checks the rendered preset against the models on
disk and against the pi catalogue, so a lane cannot drift between the router
and the client.

NVIDIA remains loaded because this workstation prioritizes CUDA availability and the
known-stable hybrid configuration over the additional battery saving from an
iGPU-only boot.

## Browsers

Install Zen from Flathub:

```sh
flatpak install -y flathub app.zen_browser.zen
```

Keep Chrome until Zen has been tested with the required development tools.
For either browser, enable inactive-tab unloading, disable background apps
after the final window closes, avoid restoring very large sessions, and remove
extensions that are not used regularly. Zen is an alternative browser, not a
guaranteed reduction in memory use for every workload.

The battery currently reports roughly 76.5% of its original full-charge
capacity. System tuning reduces idle use and pressure stalls, but a worn
battery can only be recovered through battery replacement.
