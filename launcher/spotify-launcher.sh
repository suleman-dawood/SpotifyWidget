#!/bin/bash
# spotify-launcher.sh — Launch Spotify with ad blocking and hide the window
#
# Uses LD_PRELOAD to load spotify-adblock, then hides the Spotify window
# so it runs as a background music player controlled via MPRIS DBUS.

set -euo pipefail

ADBLOCK_LIB="${SPOTIFY_ADBLOCK_LIB:-/usr/local/lib/spotify-adblock.so}"
HIDE_DELAY="${SPOTIFY_HIDE_DELAY:-3}"

log() { echo "[spotify-launcher] $*"; }

check_dependencies() {
    local missing=()
    command -v spotify >/dev/null 2>&1 || missing+=("spotify")
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
}

is_spotify_running() {
    pgrep -x spotify >/dev/null 2>&1
}

launch_spotify() {
    if is_spotify_running; then
        log "Spotify already running."
        return 0
    fi

    log "Launching Spotify with ad blocking..."
    LD_PRELOAD="$ADBLOCK_LIB" spotify &
    disown

    log "Waiting ${HIDE_DELAY}s for Spotify window..."
    sleep "$HIDE_DELAY"
}

hide_spotify_window() {
    local wid
    wid=$(xdotool search --name "Spotify" 2>/dev/null | head -1)
    if [[ -n "$wid" ]]; then
        xdotool windowminimize "$wid"
        log "Spotify window hidden."
    else
        log "WARN: Could not find Spotify window to hide."
    fi
}

show_spotify_window() {
    wmctrl -a "Spotify" 2>/dev/null || {
        log "WARN: Could not find Spotify window to show."
        return 1
    }
    log "Spotify window shown."
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
