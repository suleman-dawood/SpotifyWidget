#!/bin/bash
# spotify-launcher.sh — Launch Spotify with ad blocking and hide the window
#
# Supports both native (apt/deb) and Flatpak Spotify installations.
# Uses LD_PRELOAD to load spotify-adblock, then hides the Spotify window
# so it runs as a background music player controlled via MPRIS DBUS.

set -euo pipefail

ADBLOCK_LIB="${SPOTIFY_ADBLOCK_LIB:-/usr/local/lib/spotify-adblock.so}"
HIDE_DELAY="${SPOTIFY_HIDE_DELAY:-3}"

log() { echo "[spotify-launcher] $*"; }

# Detect install type: "native", "flatpak", or ""
detect_spotify() {
    if command -v spotify >/dev/null 2>&1; then
        echo "native"
    elif flatpak list --app 2>/dev/null | grep -q com.spotify.Client; then
        echo "flatpak"
    else
        echo ""
    fi
}

check_dependencies() {
    local missing=()
    local install_type
    install_type=$(detect_spotify)

    if [[ -z "$install_type" ]]; then
        missing+=("spotify")
    fi

    command -v wmctrl >/dev/null 2>&1 || missing+=("wmctrl")
    command -v xdotool >/dev/null 2>&1 || missing+=("xdotool")

    if [[ ! -f "$ADBLOCK_LIB" ]]; then
        missing+=("spotify-adblock ($ADBLOCK_LIB)")
    fi

    if [[ ${#missing[@]} -gt 0 ]]; then
        log "ERROR: Missing dependencies: ${missing[*]}"
        log "Run install.sh first."
        exit 1
    fi

    log "Detected Spotify install: $install_type"
}

is_spotify_running() {
    pgrep -f 'spotify' >/dev/null 2>&1
}

launch_spotify() {
    if is_spotify_running; then
        log "Spotify already running."
        return 0
    fi

    local install_type
    install_type=$(detect_spotify)

    log "Launching Spotify ($install_type) with ad blocking..."

    if [[ "$install_type" == "flatpak" ]]; then
        # Flatpak: use --env and --filesystem to inject adblock into sandbox
        flatpak run \
            --env=LD_PRELOAD="$ADBLOCK_LIB" \
            --filesystem="$(dirname "$ADBLOCK_LIB"):ro" \
            --filesystem="$HOME/.config/spotify-adblock:ro" \
            com.spotify.Client &
    else
        LD_PRELOAD="$ADBLOCK_LIB" spotify &
    fi
    disown

    log "Waiting ${HIDE_DELAY}s for Spotify window..."
    sleep "$HIDE_DELAY"
}

find_spotify_window() {
    # Try name first, fall back to class
    xdotool search --name "Spotify" 2>/dev/null | head -1 ||
    xdotool search --class "spotify" 2>/dev/null | head -1
}

hide_spotify_window() {
    local wid
    wid=$(find_spotify_window)
    if [[ -n "$wid" ]]; then
        xdotool windowminimize "$wid"
        log "Spotify window hidden."
    else
        log "WARN: Could not find Spotify window to hide."
    fi
}

show_spotify_window() {
    local wid
    wid=$(find_spotify_window)
    if [[ -n "$wid" ]]; then
        xdotool windowactivate "$wid"
        xdotool windowfocus "$wid"
        xdotool windowraise "$wid"
        log "Spotify window shown."
    else
        log "WARN: Could not find Spotify window to show."
        return 1
    fi
}

case "${1:-launch}" in
    launch)
        check_dependencies
        launch_spotify
        hide_spotify_window
        ;;
    show)
        show_spotify_window
        ;;
    hide)
        hide_spotify_window
        ;;
    status)
        if is_spotify_running; then
            echo "running"
        else
            echo "stopped"
        fi
        ;;
    *)
        echo "Usage: $0 {launch|show|hide|status}"
        exit 1
        ;;
esac
