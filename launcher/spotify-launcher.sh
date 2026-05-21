#!/bin/bash
# spotify-launcher.sh — Launch Spotify with ad blocking and hide the window
#
# Supports both native (apt/deb) and Flatpak Spotify installations.
# Uses LD_PRELOAD to load spotify-adblock, then hides the Spotify window
# so it runs as a background music player controlled via MPRIS DBUS.

set -euo pipefail

ADBLOCK_LIB="${SPOTIFY_ADBLOCK_LIB:-$HOME/.config/spotify-adblock/spotify-adblock.so}"
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
    pgrep -x spotify >/dev/null 2>&1 || flatpak ps 2>/dev/null | grep -q com.spotify.Client
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
        # Flatpak: override is set persistently, just run
        flatpak run com.spotify.Client &
    else
        LD_PRELOAD="$ADBLOCK_LIB" spotify &
    fi
    disown

    # Wait for Spotify to fully load, then hide all windows repeatedly
    # Flatpak creates windows in stages — must catch them all
    log "Waiting for Spotify windows..."
    sleep 5
    local round=0
    while [[ $round -lt 3 ]]; do
        hide_spotify_window
        sleep 2
        round=$((round + 1))
    done
    log "Hide sequence complete."
}

find_all_spotify_windows() {
    # Collect from multiple sources — Flatpak Spotify creates windows under different classes
    {
        xdotool search --class spotify 2>/dev/null || true
        wmctrl -l 2>/dev/null | grep -i "Spotify" | grep -v "SpotifyWidget" | awk '{print $1}' || true
    } | sort -u
}

find_spotify_window() {
    find_all_spotify_windows | head -1
}

hide_spotify_window() {
    local wids found=0
    wids=$(find_all_spotify_windows)
    for wid in $wids; do
        xdotool windowunmap "$wid" 2>/dev/null && found=1
    done
    if [[ $found -eq 1 ]]; then
        echo "$wids" > /tmp/.spotify-widget-wids
        log "Spotify window hidden (unmapped)."
    else
        log "WARN: Could not find Spotify window to hide."
    fi
}

show_spotify_window() {
    local found=0
    # Remap all saved windows (unmapped windows can't be found by search)
    if [[ -f /tmp/.spotify-widget-wids ]]; then
        for wid in $(cat /tmp/.spotify-widget-wids); do
            xdotool windowmap "$wid" 2>/dev/null && found=1
        done
        # Activate the main window (last one is usually the app window)
        local main_wid
        main_wid=$(tail -1 /tmp/.spotify-widget-wids)
        xdotool windowactivate "$main_wid" 2>/dev/null
        xdotool windowraise "$main_wid" 2>/dev/null
    fi

    if [[ $found -eq 1 ]]; then
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
        ;;
    show)
        show_spotify_window
        ;;
    hide)
        hide_spotify_window
        ;;
    toggle)
        # File exists + running = hidden → show
        # Running + no file = visible → hide
        # Not running = launch (clean stale file)
        if ! is_spotify_running; then
            rm -f /tmp/.spotify-widget-wids
            check_dependencies
            launch_spotify
        elif [[ -f /tmp/.spotify-widget-wids ]]; then
            show_spotify_window
            rm -f /tmp/.spotify-widget-wids
        else
            hide_spotify_window
        fi
        ;;
    status)
        if is_spotify_running; then
            echo "running"
        else
            echo "stopped"
        fi
        ;;
    *)
        echo "Usage: $0 {launch|show|hide|toggle|status}"
        exit 1
        ;;
esac
