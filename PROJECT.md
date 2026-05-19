# SpotifyWidget — Ad-Free Spotify Desktop Widget for Linux

> A minimal desktop widget that runs Spotify ad-free in the background and gives you full playback control from your desktop — no browser, no full app window needed.

---

## Problem

Spotify Free on Linux has intrusive audio ads every few songs. The options suck:

- **Spotify Premium** — $12/month
- **Web player + uBlock** — works but requires browser open, eats RAM, clutters tabs
- **spotify-adblock** — works great but you still need the full Spotify window open to control playback
- **Existing Cinnamon desklets** — "Now Playing" widgets exist but none integrate ad blocking or background playback

**No solution combines ad-free playback + minimal desktop controls + no browser/app window.**

---

## Solution

A Cinnamon desktop widget + background Spotify launcher that:

1. Launches Spotify desktop app in background with `spotify-adblock` (LD_PRELOAD)
2. Hides the Spotify window by default
3. Shows a sleek desklet on desktop: album art, song, artist, controls
4. "Open Spotify" button brings up full app when needed
5. Works across all 6 workspaces without switching

---

## Scope

### In Scope (MVP)

1. **Background Launcher**
   - Auto-launch Spotify with `spotify-adblock` on login
   - Start minimized/hidden — no visible window
   - DBUS interface for playback control

2. **Desktop Widget (Cinnamon Desklet)**
   - Album art (fetched via DBUS/MPRIS)
   - Song title + artist name
   - Play/Pause, Next, Previous buttons
   - Progress bar (current position / duration)
   - "Open Spotify" button to show full app window
   - plays queue/playlist

3. **Customization (via desklet settings)**
   - Background color, font color, accent color
   - Font scale
   - Show/hide album art
   - Widget size (compact / full)

### Out of Scope (v1)

- Playlist browsing from desklet (use full app for that)
- Lyrics display
- Queue management
- Podcast-specific controls
- Wayland support (X11 only for window hiding)

---

## Features

### Core Features

| Feature | Description | Priority |
|---------|-------------|----------|
| **Ad-free background playback** | Spotify + spotify-adblock via LD_PRELOAD, auto-hidden | P0 |
| **Now Playing display** | Album art, song, artist on desktop | P0 |
| **Playback controls** | Play/Pause, Next, Prev via MPRIS DBUS | P0 |
| **Progress bar** | Current position with seek support | P1 |
| **Open Spotify button** | Bring up full app window on demand | P0 |
| **Volume control** | Slider on desklet | P1 |
| **Shuffle/Repeat** | Toggle from desklet | P2 |
| **Customizable theme** | Colors, font scale, layout via settings | P1 |
| **Autostart** | Launch on login with ad blocking | P1 |

---

## Architecture

```
SpotifyWidget/
  desklet/
    spotify-widget@suleman/
      metadata.json         # Cinnamon desklet metadata
      settings-schema.json  # User-configurable settings
      desklet.js            # Main widget — MPRIS DBUS integration
      stylesheet.css        # Default styles
  launcher/
    spotify-launcher.sh     # Launches Spotify with LD_PRELOAD adblock
    install.sh              # Installs spotify-adblock, sets up autostart
  autostart/
    spotify-widget.desktop  # XDG autostart entry
```

---

## Tech Stack

| Layer | Technology | Why |
|-------|-----------|-----|
| **Ad Blocking** | spotify-adblock (Rust, LD_PRELOAD) | Proven, 2.2k stars, blocks audio ads |
| **Playback Control** | MPRIS DBUS (org.mpris.MediaPlayer2) | Standard Linux media player interface |
| **Widget** | Cinnamon Desklet (GJS/Clutter/St) | Native desktop widget, no extra runtime |
| **Window Management** | wmctrl / xdotool | Hide/show Spotify window |
| **Album Art** | MPRIS metadata → artUrl | No extra API calls |

### No heavy dependencies:
- No Electron/browser
- No web server
- No API keys
- No Python runtime for the widget
- Spotify desktop app is the only requirement

---

## How Ad Blocking Works

`spotify-adblock` is a Rust shared library loaded via `LD_PRELOAD`. It hooks two functions in Spotify's Chromium Embedded Framework:

1. **`getaddrinfo`** — blocks DNS resolution for ad-serving domains
2. **`cef_urlrequest_create`** — intercepts HTTP requests, blocks ad scheduling endpoints

Blocked endpoints:
- `spclient.wg.spotify.com/ads/.*`
- `spclient.wg.spotify.com/ad-logic/.*`
- `spclient.wg.spotify.com/gabo-receiver-service/.*`

Music CDNs are allowlisted so playback continues uninterrupted. When an ad slot is blocked, Spotify silently skips to the next song.

---

## DBUS Integration

All playback control uses the standard MPRIS2 interface:

```
Bus: org.mpris.MediaPlayer2.spotify
Path: /org/mpris/MediaPlayer2

Methods:
  org.mpris.MediaPlayer2.Player.PlayPause
  org.mpris.MediaPlayer2.Player.Next
  org.mpris.MediaPlayer2.Player.Previous
  org.mpris.MediaPlayer2.Player.Seek(offset)

Properties:
  org.mpris.MediaPlayer2.Player.PlaybackStatus  → "Playing" / "Paused"
  org.mpris.MediaPlayer2.Player.Metadata         → {title, artist, artUrl, length}
  org.mpris.MediaPlayer2.Player.Position         → microseconds
  org.mpris.MediaPlayer2.Player.Volume           → 0.0-1.0
  org.mpris.MediaPlayer2.Player.Shuffle          → true/false
  org.mpris.MediaPlayer2.Player.LoopStatus       → "None" / "Track" / "Playlist"
```

---

## Deliverables

### Phase 1 — Core Widget + Launcher (Week 1)

- [ ] Install script for spotify-adblock (build from source or download binary)
- [ ] Launcher script with LD_PRELOAD + window hiding
- [ ] Desklet: album art, song title, artist
- [ ] Desklet: play/pause, next, prev buttons via MPRIS
- [ ] DBUS signal listener for real-time updates (song change, play/pause)
- [ ] "Open Spotify" button (wmctrl to show window)

### Phase 2 — Polish + Settings (Week 2)

- [ ] Progress bar with seek
- [ ] Volume slider
- [ ] Shuffle/repeat toggles
- [ ] Settings: colors, font scale, compact/full layout
- [ ] Autostart desktop entry
- [ ] Handle Spotify not running (show "Launch Spotify" button)

### Phase 3 — Distribution (Week 3)

- [ ] README with screenshots, install instructions
- [ ] Submit to Cinnamon Spices (official desklet store)
- [ ] GitHub releases with pre-built spotify-adblock binary

---

## Install (User-Facing)

```bash
# 1. Install Spotify
flatpak install flathub com.spotify.Client
# or: sudo apt install spotify-client

# 2. Run installer (builds spotify-adblock, sets up autostart)
./install.sh

# 3. Add desklet
# Right-click desktop → Add Desklets → Spotify Widget
```

---

## Prior Art

| Project | Stars | What It Does | Gap |
|---------|-------|-------------|-----|
| spotify-adblock | 2.2k | LD_PRELOAD ad blocker | No widget/UI, just ad blocking |
| SpotX-Bash | 5.4k | Binary patching ad blocker | Fragile, breaks on updates |
| cinnamon-spices-desklets | — | Various desklets | No Spotify desklet with ad blocking |
| spotify-tui | 16k | Terminal Spotify client | No desktop widget, no ad blocking |

**SpotifyWidget combines the best ad blocker (spotify-adblock) with a native desktop widget. Nothing else does this.**
