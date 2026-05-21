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

    # Retry hiding until window appears (Flatpak can be slow)
    local attempts=0
    while [[ $attempts -lt 10 ]]; do
        sleep 1
        local wids
        wids=$(find_all_spotify_windows)
        if [[ -n "$wids" ]]; then
            log "Found Spotify window after $((attempts+1))s."
            sleep 1  # Let it fully render
            hide_spotify_window
            return 0
        fi
        attempts=$((attempts + 1))
    done
    log "WARN: Spotify window not found after 10s."
}

find_all_spotify_windows() {
    # Collect from multiple sources — Flatpak Spotify creates windows under different classes
    {
        xdotool search --class spotify 2>/dev/null
        wmctrl -l 2>/dev/null | grep -i "Spotify" | grep -v "SpotifyWidget" | awk '{print $1}'
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
    # Remap saved windows (unmapped windows can't be found by search)
    if [[ -f /tmp/.spotify-widget-wids ]]; then
        while read -r wid; do
            [[ -z "$wid" ]] && continue
            if xprop -id "$wid" >/dev/null 2>&1; then
                xdotool windowmap "$wid" 2>/dev/null
                xdotool windowactivate "$wid" 2>/dev/null
                xdotool windowfocus "$wid" 2>/dev/null
                xdotool windowraise "$wid" 2>/dev/null
                found=1
            fi
        done < /tmp/.spotify-widget-wids
    fi

    # Fallback: search for any visible spotify window
    if [[ $found -eq 0 ]]; then
        local wid
        wid=$(find_spotify_window)
        if [[ -n "$wid" ]]; then
            xdotool windowactivate "$wid" 2>/dev/null
            found=1
        fi
    fi

    if [[ $found -eq 1 ]]; then
        log "Spotify window shown."
    else
        log "WARN: Could not find Spotify window to show."
        return 1
    fi
}

# Watch mode: monitor Spotify window, re-hide if it gets closed
# This keeps Spotify running in background — closing the window just hides it
watch_and_guard() {
    log "Watching Spotify window (close = hide)..."
    while is_spotify_running; do
        local wid
        wid=$(find_spotify_window)
        if [[ -z "$wid" ]] && is_spotify_running; then
            # Window gone but process alive — window was closed
            # Wait for it to potentially reappear (some apps recreate windows)
            sleep 1
            if [[ -z "$(find_spotify_window)" ]] && is_spotify_running; then
                log "Spotify window closed but still running — music continues."
            fi
        fi
        sleep 2
    done
    log "Spotify process exited."
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
    watch)
        watch_and_guard
        ;;
    status)
        if is_spotify_running; then
            echo "running"
        else
            echo "stopped"
        fi
        ;;
    *)
        echo "Usage: $0 {launch|show|hide|watch|status}"
        exit 1
        ;;
esac
