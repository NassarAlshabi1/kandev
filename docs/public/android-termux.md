---
title: "Android (Termux)"
description: "Run the Kandev server on an Android phone with Termux: install, build, add agents, and reach it from other devices."
---

# Run Kandev on Android with Termux

This guide runs the full Kandev server (web UI + API + agent runtime) natively
on an aarch64 Android phone using [Termux](https://termux.dev), and explains
how to reach that server from other devices.

The build is a regular Android (bionic) executable, not a proot Linux distro:
kandev and agentctl are cross-compiled with the Android NDK for
`GOOS=android GOARCH=arm64` (Android 7.0 / API 24+), so they run directly
under Termux alongside the agents they manage.

## Requirements

- An aarch64 (64-bit ARM) phone with Android 7.0 or newer.
- **Termux from F-Droid or [GitHub releases](https://github.com/termux/termux-app/releases).**
  Do not use the Play Store build: it targets newer SDK levels, and Android
  10+ blocks executing downloaded binaries from those app sandboxes (the
  installer detects this and tells you).
- Roughly 600 MB free storage for the binaries plus task data.
- Wi-Fi (or another always-on network) while agents run.

## Install a prebuilt bundle

Every `build-android` workflow run and every release produced with the
`release_tag` input publishes `kandev-android-arm64.tar.gz` containing
`bin/kandev`, `bin/agentctl`, `install.sh`, and quick-start notes.

Inside Termux:

```bash
pkg update
# From a release:
curl -L --fail -o kandev-android-arm64.tar.gz \
  https://github.com/<owner>/<repo>/releases/latest/download/kandev-android-arm64.tar.gz
tar -xzf kandev-android-arm64.tar.gz
cd kandev-android-arm64
bash install.sh
```

`install.sh` checks the device (Termux, aarch64), verifies the binary executes,
copies kandev + agentctl to `~/.kandev/bin`, creates a `kandev` launcher on
`$PATH`, and prints first-run steps. Uninstall any time with
`bash install.sh --uninstall` (removes the launcher and `~/.kandev`,
including task data).

If you have the tarball locally (for example a workflow artifact), skip the
download and run `bash install.sh --file /path/to/kandev-android-arm64.tar.gz`.

## Start the server

```bash
kandev
```

The first start creates `~/.kandev`, runs migrations, and prints the local
URL (for example `http://localhost:3000`). Open it in the phone browser: the
UI is the same responsive web app described in
[mobile-remote-access.md](mobile-remote-access.md). Useful variants:

```bash
kandev --port 8080     # different port
kandev --verbose       # info logs on stdout
~/.kandev/bin/kandev --help
```

Logs live in `~/.kandev/logs/`.

## Install AI agents on the phone

Kandev drives agent CLIs it finds on `PATH`. In Termux:

```bash
pkg install nodejs-lts git ripgrep
npm install -g @anthropic-ai/claude-code   # or another supported agent CLI
claude --version
```

Restart the kandev server after installing agents so they are discovered, then
pick the agent from Settings → Agent profiles. Agents share the Termux
environment (git credentials, `gh`, SSH keys in `~/.ssh`), so sign in exactly
as you would on a Linux machine. For heavier parallel runs, prefer a remote
runtime (SSH executor) for some tasks; the phone stays the control plane
either way.

## Reach the phone from other devices

The server binds `0.0.0.0` so other devices can connect over a protected
boundary. The recommended path is Tailscale:

```bash
pkg install tailscale   # or: curl -fsSL https://tailscale.com/install.sh | sh
tailscale up
```

Then open `http://<phone-tailscale-ip>:<port>` from any device on your
tailnet. Cloudflare Tunnel and private VPNs work the same way. See
[mobile-remote-access.md](mobile-remote-access.md) for the patterns and the
security notes around unauthenticated origins.

## Keep Android from killing the server

```bash
termux-wake-lock        # hold a wake lock while agents run (termux-wake-unlock to release)
```

Also disable battery optimization for Termux (Android Settings → Apps →
Termux → Battery → Unrestricted). Long agent runs without this are suspended
when the screen turns off. Acquire the wake lock before starting kandev and
release it when done to spare the battery.

## Build the bundle yourself

On any Linux/macOS build machine with Go 1.26+, Node 24, pnpm 9.15.9, and an
Android NDK (r21+ tested with r27c):

```bash
export ANDROID_NDK_HOME=/path/to/android-ndk-r27c
make build-android        # web + kandev-android-arm64 + agentctl-android-arm64
make package-android      # → dist/kandev-android-arm64.tar.gz
```

`build-android` reuses the standard web pipeline (`build-web` +
`sync-embedded-web`) and cross-compiles with the NDK bionic toolchain
(`aarch64-linux-android24-clang`, `CGO_ENABLED=1` because SQLite uses
mattn/go-sqlite3). The pure-Go agentctl helper builds without the NDK.
The [build-android workflow](../../.github/workflows/build-android.yml) does
the same on GitHub runners; trigger it from the Actions tab and download the
artifact, or pass an existing tag in `release_tag` to attach the tarball to a
release.

## Security notes

- The server ships without authentication and binds `0.0.0.0`. Before
  exposing it beyond loopback, enable authentication
  (Settings → System → Feature Toggles, or `export KANDEV_FEATURES_AUTH=true`)
  and keep the phone on a protected boundary (Tailscale, VPN).
- Loopback-only operation: `export KANDEV_SERVER_HOST=127.0.0.1` before
  starting the server.
- Anyone who can reach an unauthenticated origin has administrator access:
  the same warning as the remote-access guide applies on a phone.

## Troubleshooting

- **`exec` fails with code 126 / "Permission denied"**: you are on the Play
  Store Termux build. Switch to F-Droid or the GitHub APK and reinstall the
  bundle.
- **`kandev: not found` after install**: open a new Termux session so
  `$PATH` picks up `$PREFIX/bin`, or run `hash -r`.
- **DNS failures from the server process** (rare with the bionic build): some
  networks and older Android versions need a resolver file. Install proot and
  run the server through a bind:
  `pkg install proot && proot -b $PREFIX/etc/resolv.conf:/etc/resolv.conf kandev start`
- **Port already in use**: pick another port with `kandev --port 8080`, or
  stop the previous instance (`pkill kandev`).
- **Server dies when the screen turns off**: apply the wake lock and battery
  optimization steps above.
- **agentctl errors at startup**: agentctl must sit next to the kandev
  binary (`~/.kandev/bin/agentctl`); the installer arranges this, so re-run
  `bash install.sh` if you moved files manually.
