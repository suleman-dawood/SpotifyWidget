# SpotifyWidget

Ad-free Spotify desktop widget for Linux Mint / Cinnamon. Runs Spotify in the background with [spotify-adblock](https://github.com/abba23/spotify-adblock), controlled from a minimal desktop desklet.

No browser. No full app window. No ads.

## What it does

- Blocks Spotify audio ads via LD_PRELOAD hook
- Shows album art, track info, and playback controls on your desktop
- Play/pause, next, previous, seek, volume — all from the desklet
- Opens the full Spotify app on demand, hides it when you don't need it
- Auto-relaunches Spotify if the window is closed (music keeps playing)

## Requirements

- **Linux Mint** with Cinnamon desktop (or any distro with Cinnamon 5.4+)
- **X11** session (Wayland not supported for window management)
- **Spotify** — Flatpak or native .deb install
- **Rust toolchain** — to build spotify-adblock from source

## Install

### 1. Install system dependencies

```bash
sudo apt install -y wmctrl xdotool
```

### 2. Install Spotify

```bash
# Flatpak (recommended)
flatpak install -y flathub com.spotify.Client

# Or native .deb
# See https://www.spotify.com/download/linux/
```

### 3. Build and install spotify-adblock

```bash
# Install Rust if needed
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
source "$HOME/.cargo/env"

# Build
git clone --depth 1 https://github.com/abba23/spotify-adblock.git /tmp/spotify-adblock
cd /tmp/spotify-adblock && cargo build --release

# Install
mkdir -p ~/.config/spotify-adblock
cp target/release/libspotifyadblock.so ~/.config/spotify-adblock/spotify-adblock.so
cp config.toml ~/.config/spotify-adblock/
cd - && rm -rf /tmp/spotify-adblock
```

For **Flatpak** users, set the override so adblock loads inside the sandbox:

```bash
flatpak override --user \
  --env=LD_PRELOAD=$HOME/.config/spotify-adblock/spotify-adblock.so \
  --filesystem=home:ro \
  com.spotify.Client
```

### 4. Install the desklet

```bash
# Clone this repo
git clone https://github.com/suleman-dawood/SpotifyWidget.git
cd SpotifyWidget

# Symlink desklet to Cinnamon
ln -sf "$(pwd)/desklet/spotify-widget@suleman" \
  ~/.local/share/cinnamon/desklets/spotify-widget@suleman
```

Then: **Right-click desktop → Add Desklets → Spotify Widget**

## Usage

| Action | How |
|--------|-----|
| **Play/Pause** | Click the play button on the desklet |
| **Next/Previous** | Click skip buttons |
| **Seek** | Click anywhere on the progress bar |
| **Volume** | Click the volume icon to toggle slider, or scroll on the icon |
| **Open Spotify** | Click the Spotify icon — shows the full app window |
| **Kill Spotify** | Click the X button — stops Spotify completely |
| **Launch Spotify** | Click play or the Spotify icon after killing |

## Configuration

Right-click the desklet → **Configure**:

| Setting | Description |
|---------|-------------|
| Background color | Widget background |
| Font color | Text color |
| Accent color | Progress bar, highlights |
| Font scale | 0.5x – 2.0x |
| Show album art | Toggle album art display |
| Widget size | Compact or Full |
| Widget width | 200 – 1500 px |
| Refresh interval | Position update frequency (500-5000ms) |
| Launcher path | Custom path to spotify-launcher.sh |

## How ad blocking works

[spotify-adblock](https://github.com/abba23/spotify-adblock) is a Rust shared library loaded via `LD_PRELOAD`. It hooks `getaddrinfo` (DNS) and `cef_urlrequest_create` (HTTP) inside Spotify's Chromium runtime, blocking ad-serving domains and endpoints. Music CDNs are allowlisted — playback is uninterrupted.

## Project structure

```
SpotifyWidget/
  desklet/
    spotify-widget@suleman/
      metadata.json         # Cinnamon desklet metadata
      settings-schema.json  # Configurable settings
      desklet.js            # MPRIS DBUS integration + UI
      stylesheet.css        # Default styles
  launcher/
    spotify-launcher.sh     # Launch/show/hide/kill Spotify
    install.sh              # Build spotify-adblock + install deps
  autostart/
    spotify-widget.desktop  # XDG autostart entry (optional)
  tests/
    test_launcher.sh        # Unit tests
```

## License

MIT
