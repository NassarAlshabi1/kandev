Kandev for Android (Termux) — android/arm64
============================================

Quick install (inside Termux, from the folder you unpacked this archive into):

    bash install.sh

Then start the server:

    kandev

The first start prints a local URL such as http://localhost:PORT — open it in
your phone browser. agentctl must stay next to the kandev binary (the
installer already places both under ~/.kandev/bin and creates a `kandev`
launcher on $PATH).

What is inside this archive
---------------------------
  bin/kandev          Kandev server (android/arm64, bionic, Android 7.0+/API 24+).
                      The web UI and API are embedded in this single binary.
  bin/agentctl        Agent runtime sidecar; the server refuses to start without it.
  install.sh          Termux installer (launcher + first-run guidance).
  README-termux.txt   This file.

Requirements
------------
  - Termux built from F-Droid or GitHub releases (the Play Store build blocks
    executing downloaded binaries on Android 10+).
  - aarch64 (64-bit ARM) device.

Security
--------
The server binds 0.0.0.0 by default and ships without authentication. Before
reaching it from any other device, enable authentication (Settings > System >
Feature Toggles, or export KANDEV_FEATURES_AUTH=true) or keep it inside a
private network boundary such as Tailscale. To bind loopback only, export
KANDEV_SERVER_HOST=127.0.0.1.

Long-running agents
-------------------
Run `termux-wake-lock` before long tasks and disable battery optimization for
Termux, or Android will suspend the server mid-run.

Full documentation: docs/public/android-termux.md in the repository.
