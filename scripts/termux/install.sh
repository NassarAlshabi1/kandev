#!/usr/bin/env bash
# Kandev Termux installer
#
# Installs the android/arm64 kandev server and agentctl sidecar into Termux,
# creates a `kandev` launcher on $PATH, and prints first-run instructions.
#
# Usage (inside Termux, from the unpacked bundle directory):
#   bash install.sh                          # install from ./bin next to this script
#   bash install.sh --file kandev-android-arm64.tar.gz
#   bash install.sh --release                # download latest release tarball
#   bash install.sh --release --repo OWNER/NAME
#   bash install.sh --uninstall
#
# Requirements: Termux (F-Droid or GitHub build, NOT the Play Store build),
# aarch64 device, Android 7.0+ (API 24+).
set -euo pipefail

DEFAULT_REPO="NassarAlshabi1/kandev"
ASSET_NAME="kandev-android-arm64.tar.gz"
INSTALL_DIR="$HOME/.kandev"
PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
LAUNCHER="$PREFIX/bin/kandev"

log()  { printf '\033[1;36m[kandev]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[kandev]\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m[kandev]\033[0m %s\n' "$*" >&2; exit 1; }

MODE="local"
FILE=""
REPO="${KANDEV_GITHUB_REPO:-$DEFAULT_REPO}"

while [ $# -gt 0 ]; do
    case "$1" in
        --file)      MODE="file"; FILE="${2:-}"; shift 2 ;;
        --release)   MODE="release"; shift ;;
        --repo)      REPO="$2"; shift 2 ;;
        --uninstall) MODE="uninstall"; shift ;;
        -h|--help)   sed -n '2,16p' "$0"; exit 0 ;;
        *)           die "unknown option: $1 (try --help)" ;;
    esac
done

uninstall() {
    rm -f "$LAUNCHER"
    rm -rf "$INSTALL_DIR"
    log "Removed $LAUNCHER and $INSTALL_DIR (task data in ~/.kandev/data was removed too)."
}

# --- Environment checks (also guard --uninstall: ~/.kandev is the same
# default data directory the desktop server uses, so never touch it outside
# a real Termux environment) -----------------------------------------------

IS_TERMUX=0
[ -n "${TERMUX_VERSION:-}" ] && IS_TERMUX=1
[ -d "/data/data/com.termux/files" ] && IS_TERMUX=1
[ "$IS_TERMUX" = "1" ] || die "This installer must run inside Termux (Android). Get it from F-Droid or github.com/termux/termux-app/releases — do NOT use the Play Store build."

ARCH="$(uname -m)"
case "$ARCH" in
    aarch64|arm64|armv8*) : ;;
    *) die "Unsupported architecture: $ARCH. Kandev android bundles are built for aarch64 (64-bit ARM) phones." ;;
esac

if [ ! -x "$PREFIX/bin/pkg" ]; then
    die "pkg not found at $PREFIX/bin/pkg — is this a full Termux install?"
fi

[ "$MODE" = "uninstall" ] && uninstall

# --- Acquire the binaries ----------------------------------------------------

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

case "$MODE" in
    file)
        [ -n "$FILE" ] || die "--file requires a path to $ASSET_NAME"
        [ -f "$FILE" ] || die "file not found: $FILE"
        log "Unpacking $FILE"
        tar -xzf "$FILE" -C "$WORK"
        SRC="$WORK/kandev-android-arm64/bin"
        ;;
    release)
        URL="https://github.com/$REPO/releases/latest/download/$ASSET_NAME"
        log "Downloading latest android/arm64 release from github.com/$REPO"
        curl -L --fail --retry 3 -o "$WORK/$ASSET_NAME" "$URL" \
            || die "Download failed. Check your connection, or that a release with asset $ASSET_NAME exists at github.com/$REPO/releases"
        tar -xzf "$WORK/$ASSET_NAME" -C "$WORK"
        SRC="$WORK/kandev-android-arm64/bin"
        ;;
    local)
        # install.sh sits at the bundle root, next to bin/
        SRC="$(cd -- "$(dirname -- "$0")" && pwd)"
        if [ -f "$SRC/bin/kandev" ]; then
            SRC="$SRC/bin"
        fi
        ;;
esac

[ -x "$SRC/kandev" ]   || { ls -la "$SRC" >&2 || true; die "kandev binary missing in the bundle (expected $SRC/kandev)"; }
[ -x "$SRC/agentctl" ] || die "agentctl binary missing in the bundle (expected $SRC/agentctl)"

# --- Sanity-check the binary actually executes on this device -----------------

if ! "$SRC/kandev" --version >/dev/null 2>&1; then
    rc=$?
    if [ "$rc" = 126 ] || [ "$rc" = 13 ]; then
        die "exec failed (code $rc). If you installed Termux from the Play Store, the OS blocks executing downloaded binaries. Install Termux from F-Droid or github.com/termux/termux-app/releases, then retry."
    fi
    die "kandev --version failed (code $rc). See docs/public/android-termux.md (troubleshooting)."
fi
log "Binary check OK: $("$SRC/kandev" --version 2>/dev/null || echo 'kandev')"

# --- Install ------------------------------------------------------------------

log "Installing to $INSTALL_DIR/bin"
mkdir -p "$INSTALL_DIR/bin"
cp "$SRC/kandev" "$INSTALL_DIR/bin/kandev"
cp "$SRC/agentctl" "$INSTALL_DIR/bin/agentctl"
chmod 755 "$INSTALL_DIR/bin/kandev" "$INSTALL_DIR/bin/agentctl"

log "Creating launcher $LAUNCHER"
cat > "$LAUNCHER" <<LAUNCHER
#!/data/data/com.termux/files/usr/bin/sh
# Kandev launcher (created by scripts/termux/install.sh)
# Extra flags are passed to 'kandev start', e.g.: kandev --port 8080
# Remote access from other devices: see docs/public/android-termux.md.
# Keep the Wi-Fi awake during long agent runs:  termux-wake-lock
exec "\$HOME/.kandev/bin/kandev" start "\$@"
LAUNCHER
chmod 755 "$LAUNCHER"

# --- First-run guidance -------------------------------------------------------

log "Installed. Next steps:"
cat <<NEXT

  1. Start the server:            kandev
     (first start creates ~/.kandev and prints the local URL)

  2. Open the UI on this phone:   http://localhost:PORT  (port is printed at start)

  3. Install AI agents in Termux, e.g. Claude Code:
       pkg install nodejs-lts git
       npm config set os android 2>/dev/null || true
       npm install -g @anthropic-ai/claude-code

  4. Reach this server from other devices (Tailscale recommended):
       pkg install tailscale        # or: curl -fsSL https://tailscale.com/install.sh | sh
       tailscale up
     Then open http://<phone-tailscale-ip>:PORT from any device on your tailnet.

  5. Security notes:
       - The server binds 0.0.0.0 by default. Enable authentication
         (Settings > System > Feature Toggles, or export KANDEV_FEATURES_AUTH=true)
         before exposing it beyond loopback.
       - To bind loopback only:  export KANDEV_SERVER_HOST=127.0.0.1
       - Run 'termux-wake-lock' before long agent runs, and disable battery
         optimization for Termux so Android does not kill the server.

  Full guide: docs/public/android-termux.md in the repository.
NEXT
