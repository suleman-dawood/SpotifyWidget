#!/bin/bash
# install.sh — Install spotify-adblock, set up launcher, configure autostart
#
# Builds spotify-adblock from source (requires Rust toolchain) and installs
# the shared library + config. Sets up XDG autostart for the launcher.

set -euo pipefail

INSTALL_DIR="/usr/local/lib"
CONFIG_DIR="$HOME/.config/spotify-adblock"
AUTOSTART_DIR="$HOME/.config/autostart"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="/tmp/spotify-adblock-build"

log() { echo "[install] $*"; }

install_system_deps() {
    log "Installing system dependencies..."
    sudo apt-get update -qq
    sudo apt-get install -y -qq wmctrl xdotool spotify-client 2>/dev/null || {
        log "WARN: Some packages may need manual installation."
        log "  - wmctrl: sudo apt install wmctrl"
        log "  - xdotool: sudo apt install xdotool"
        log "  - spotify: see https://www.spotify.com/download/linux/"
    }
}

install_rust() {
    if command -v cargo >/dev/null 2>&1; then
        log "Rust toolchain found."
        return 0
    fi
    log "Installing Rust toolchain..."
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    source "$HOME/.cargo/env"
}

build_adblock() {
    log "Building spotify-adblock..."
    rm -rf "$BUILD_DIR"
    git clone --depth 1 https://github.com/abba23/spotify-adblock.git "$BUILD_DIR"
    cd "$BUILD_DIR"
    cargo build --release
    log "Build complete."
}

install_adblock() {
    log "Installing spotify-adblock library..."
    sudo cp "$BUILD_DIR/target/release/libspotifyadblock.so" "$INSTALL_DIR/spotify-adblock.so"
    sudo chmod 644 "$INSTALL_DIR/spotify-adblock.so"

    mkdir -p "$CONFIG_DIR"
    if [[ -f "$BUILD_DIR/config.toml" ]]; then
        cp "$BUILD_DIR/config.toml" "$CONFIG_DIR/config.toml"
    fi
    log "Library installed to $INSTALL_DIR/spotify-adblock.so"
}

setup_autostart() {
    log "Setting up autostart..."
    mkdir -p "$AUTOSTART_DIR"
    cp "$PROJECT_DIR/autostart/spotify-widget.desktop" "$AUTOSTART_DIR/"
    log "Autostart configured."
}

setup_launcher() {
    chmod +x "$SCRIPT_DIR/spotify-launcher.sh"
    log "Launcher ready at $SCRIPT_DIR/spotify-launcher.sh"
}

cleanup() {
    rm -rf "$BUILD_DIR"
    log "Cleaned up build directory."
}

main() {
    log "=== SpotifyWidget Installer ==="
    install_system_deps
    install_rust
    build_adblock
    install_adblock
    setup_launcher
    setup_autostart
    cleanup
    log "=== Installation complete ==="
    log ""
    log "Next steps:"
    log "  1. Add the Spotify Widget desklet: Right-click desktop → Add Desklets"
    log "  2. Or launch manually: $SCRIPT_DIR/spotify-launcher.sh"
}

main "$@"
