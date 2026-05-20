// Spotify Widget — Cinnamon Desklet
// MPRIS DBUS integration for ad-free Spotify playback control

const Desklet = imports.ui.desklet;
const St = imports.gi.St;
const GLib = imports.gi.GLib;
const Gio = imports.gi.Gio;
const Clutter = imports.gi.Clutter;
const Settings = imports.ui.settings;
const Util = imports.misc.util;
const Lang = imports.lang;
const Mainloop = imports.mainloop;
const Gettext = imports.gettext;

const UUID = "spotify-widget@suleman";

const MPRIS_BUS_NAME = "org.mpris.MediaPlayer2.spotify";
const MPRIS_OBJECT_PATH = "/org/mpris/MediaPlayer2";
const MPRIS_PLAYER_IFACE = "org.mpris.MediaPlayer2.Player";
const MPRIS_ROOT_IFACE = "org.mpris.MediaPlayer2";
const DBUS_PROPERTIES_IFACE = "org.freedesktop.DBus.Properties";

// DBUS XML interfaces for proxy creation
const MprisPlayerIface = `
<node>
  <interface name="${MPRIS_PLAYER_IFACE}">
    <method name="PlayPause"/>
    <method name="Next"/>
    <method name="Previous"/>
    <method name="Stop"/>
    <method name="Seek">
      <arg type="x" direction="in"/>
    </method>
    <method name="SetPosition">
      <arg type="o" direction="in"/>
      <arg type="x" direction="in"/>
    </method>
    <property name="PlaybackStatus" type="s" access="read"/>
    <property name="Metadata" type="a{sv}" access="read"/>
    <property name="Position" type="x" access="read"/>
    <property name="Volume" type="d" access="readwrite"/>
    <property name="Shuffle" type="b" access="readwrite"/>
    <property name="LoopStatus" type="s" access="readwrite"/>
    <signal name="Seeked">
      <arg type="x"/>
    </signal>
  </interface>
</node>`;

const MprisPlayerProxy = Gio.DBusProxy.makeProxyWrapper(MprisPlayerIface);

const DBusPropertiesIface = `
<node>
  <interface name="${DBUS_PROPERTIES_IFACE}">
    <method name="Get">
      <arg type="s" direction="in"/>
      <arg type="s" direction="in"/>
      <arg type="v" direction="out"/>
    </method>
    <method name="GetAll">
      <arg type="s" direction="in"/>
      <arg type="a{sv}" direction="out"/>
    </method>
    <signal name="PropertiesChanged">
      <arg type="s"/>
      <arg type="a{sv}"/>
      <arg type="as"/>
    </signal>
  </interface>
</node>`;

const DBusPropertiesProxy = Gio.DBusProxy.makeProxyWrapper(DBusPropertiesIface);


function SpotifyWidget(metadata, deskletId) {
    this._init(metadata, deskletId);
}

SpotifyWidget.prototype = {
    __proto__: Desklet.Desklet.prototype,

    _init: function(metadata, deskletId) {
        Desklet.Desklet.prototype._init.call(this, metadata, deskletId);

        this._metadata = metadata;
        this._deskletId = deskletId;
        this._playerProxy = null;
        this._propsProxy = null;
        this._propsSignalId = 0;
        this._positionTimerId = 0;
        this._currentTrackLength = 0;
        this._currentPosition = 0;
        this._isPlaying = false;
        this._currentVolume = 1.0;
        this._currentTrackId = "";
        this._isSeeking = false;

        this._bindSettings();
        this._buildUI();
        this._connectDBus();
        this._startPositionPolling();
    },

    // --- Settings ---

    _bindSettings: function() {
        this.settings = new Settings.DeskletSettings(this, UUID, this._deskletId);

        this.settings.bind("background-color", "backgroundColor", this._onSettingsChanged.bind(this));
        this.settings.bind("font-color", "fontColor", this._onSettingsChanged.bind(this));
        this.settings.bind("accent-color", "accentColor", this._onSettingsChanged.bind(this));
        this.settings.bind("font-scale", "fontScale", this._onSettingsChanged.bind(this));
        this.settings.bind("show-album-art", "showAlbumArt", this._onSettingsChanged.bind(this));
        this.settings.bind("widget-size", "widgetSize", this._onSettingsChanged.bind(this));
        this.settings.bind("refresh-interval", "refreshInterval", this._onRefreshIntervalChanged.bind(this));
        this.settings.bind("launcher-path", "launcherPath");
    },

    _onSettingsChanged: function() {
        this._applyStyles();
    },

    _onRefreshIntervalChanged: function() {
        this._stopPositionPolling();
        this._startPositionPolling();
    },

    // --- UI Construction ---

    _buildUI: function() {
        // Main container
        this._container = new St.BoxLayout({
            vertical: true,
            style_class: "spotify-widget",
            reactive: true
        });

        // Album art
        this._albumArt = new St.Bin({
            style_class: "album-art",
            x_align: St.Align.MIDDLE
        });
        this._albumArtIcon = new St.Icon({
            icon_name: "media-optical",
            icon_size: 120
        });
        this._albumArt.set_child(this._albumArtIcon);

        // Track info
        this._trackTitle = new St.Label({
            text: "Not Playing",
            style_class: "track-title"
        });
        this._trackArtist = new St.Label({
            text: "",
            style_class: "track-artist"
        });

        // Controls
        this._controlsBox = new St.BoxLayout({
            style_class: "controls-box",
            x_align: St.Align.MIDDLE
        });

        this._prevButton = this._createControlButton("media-skip-backward-symbolic", this._onPrevious.bind(this));
        this._playPauseButton = this._createControlButton("media-playback-start-symbolic", this._onPlayPause.bind(this));
        this._playPauseButton.add_style_class_name("play-pause-button");
        this._nextButton = this._createControlButton("media-skip-forward-symbolic", this._onNext.bind(this));

        this._controlsBox.add_actor(this._prevButton);
        this._controlsBox.add_actor(this._playPauseButton);
        this._controlsBox.add_actor(this._nextButton);

        // Seekable progress bar — click to seek
        this._progressContainer = new St.BoxLayout({
            style_class: "progress-container",
            x_expand: true,
            reactive: true,
            track_hover: true
        });
        this._progressBar = new St.Bin({
            style_class: "progress-bar"
        });
        this._progressBg = new St.Bin({
            style_class: "progress-bg",
            x_expand: true
        });
        this._progressContainer.add_actor(this._progressBar);
        this._progressContainer.add_actor(this._progressBg);

        this._progressContainer.connect("button-press-event", (actor, event) => {
            this._onProgressClicked(actor, event);
            return Clutter.EVENT_STOP;
        });

        // Position label
        this._positionLabel = new St.Label({
            text: "",
            style: "font-size: 10px; opacity: 0.6; margin-top: 4px;"
        });

        // Volume slider
        this._volumeBox = new St.BoxLayout({
            style_class: "volume-box",
            x_align: St.Align.MIDDLE
        });
        this._volumeIcon = new St.Icon({
            icon_name: "audio-volume-high-symbolic",
            icon_size: 14
        });
        this._volumeSliderContainer = new St.BoxLayout({
            style_class: "volume-slider-container",
            reactive: true,
            track_hover: true,
            x_expand: true
        });
        this._volumeSliderFill = new St.Bin({
            style_class: "volume-slider-fill"
        });
        this._volumeSliderBg = new St.Bin({
            style_class: "volume-slider-bg",
            x_expand: true
        });
        this._volumeSliderContainer.add_actor(this._volumeSliderFill);
        this._volumeSliderContainer.add_actor(this._volumeSliderBg);

        this._volumeSliderContainer.connect("button-press-event", (actor, event) => {
            this._onVolumeClicked(actor, event);
            return Clutter.EVENT_STOP;
        });
        this._volumeSliderContainer.connect("scroll-event", (actor, event) => {
            this._onVolumeScroll(actor, event);
            return Clutter.EVENT_STOP;
        });

        this._volumeLabel = new St.Label({
            text: "100%",
            style: "font-size: 10px; opacity: 0.6; min-width: 32px;"
        });
        this._volumeBox.add_actor(this._volumeIcon);
        this._volumeBox.add_actor(this._volumeSliderContainer);
        this._volumeBox.add_actor(this._volumeLabel);

        // Open Spotify button
        this._openButton = new St.Button({
            label: "Open Spotify",
            style_class: "open-spotify-button",
            reactive: true
        });
        this._openButton.connect("clicked", this._onOpenSpotify.bind(this));

        // Status label (shown when Spotify not running)
        this._statusLabel = new St.Label({
            text: "Spotify is not running",
            style_class: "status-label",
            visible: false
        });

        // Launch button (shown when Spotify not running)
        this._launchButton = new St.Button({
            label: "Launch Spotify",
            style_class: "open-spotify-button",
            reactive: true,
            visible: false
        });
        this._launchButton.connect("clicked", this._onLaunchSpotify.bind(this));

        // Assemble
        this._container.add_actor(this._albumArt);
        this._container.add_actor(this._trackTitle);
        this._container.add_actor(this._trackArtist);
        this._container.add_actor(this._controlsBox);
        this._container.add_actor(this._progressContainer);
        this._container.add_actor(this._positionLabel);
        this._container.add_actor(this._volumeBox);
        this._container.add_actor(this._openButton);
        this._container.add_actor(this._statusLabel);
        this._container.add_actor(this._launchButton);

        this._applyStyles();
        this.setContent(this._container);
    },

    _createControlButton: function(iconName, callback) {
        let button = new St.Button({
            style_class: "control-button",
            reactive: true
        });
        let icon = new St.Icon({
            icon_name: iconName,
            icon_size: 20
        });
        button.set_child(icon);
        button.connect("clicked", callback);
        return button;
    },

    _applyStyles: function() {
        let bg = this.backgroundColor || "rgba(24, 24, 24, 0.85)";
        let fg = this.fontColor || "rgba(255, 255, 255, 1.0)";
        let accent = this.accentColor || "rgba(30, 215, 96, 1.0)";
        let scale = this.fontScale || 1.0;
        let isCompact = this.widgetSize === "compact";

        this._container.set_style(
            `background-color: ${bg}; color: ${fg}; font-size: ${Math.round(14 * scale)}px;`
        );

        if (isCompact) {
            this._container.remove_style_class_name("spotify-widget");
            this._container.add_style_class_name("spotify-widget-compact");
            this._albumArtIcon.set_icon_size(60);
        } else {
            this._container.remove_style_class_name("spotify-widget-compact");
            this._container.add_style_class_name("spotify-widget");
            this._albumArtIcon.set_icon_size(120);
        }

        this._trackTitle.set_style(`color: ${fg}; font-size: ${Math.round(14 * scale)}px; font-weight: bold;`);
        this._trackArtist.set_style(`color: ${fg}; font-size: ${Math.round(12 * scale)}px; opacity: 0.7;`);

        this._progressContainer.set_style(
            `background-color: rgba(255,255,255,0.15); height: 4px; border-radius: 2px; margin-top: 8px;`
        );
        this._progressBar.set_style(
            `background-color: ${accent}; height: 4px; border-radius: 2px;`
        );

        this._controlsBox.get_children().forEach(function(btn) {
            btn.set_style(`color: ${fg};`);
        });

        this._openButton.set_style(
            `background-color: ${accent}; color: rgba(0,0,0,1); padding: 4px 12px; border-radius: 16px; font-size: ${Math.round(11 * scale)}px;`
        );
        this._launchButton.set_style(
            `background-color: ${accent}; color: rgba(0,0,0,1); padding: 4px 12px; border-radius: 16px; font-size: ${Math.round(11 * scale)}px;`
        );

        this._volumeIcon.set_style(`color: ${fg};`);
        this._volumeLabel.set_style(`color: ${fg}; font-size: ${Math.round(10 * scale)}px; opacity: 0.6; min-width: 32px;`);

        this._albumArt.visible = this.showAlbumArt !== false;
    },

    // --- DBUS Connection ---

    _connectDBus: function() {
        try {
            this._playerProxy = new MprisPlayerProxy(
                Gio.DBus.session,
                MPRIS_BUS_NAME,
                MPRIS_OBJECT_PATH
            );

            this._propsProxy = new DBusPropertiesProxy(
                Gio.DBus.session,
                MPRIS_BUS_NAME,
                MPRIS_OBJECT_PATH
            );

            // Listen for property changes (song change, play/pause)
            this._propsSignalId = this._propsProxy.connectSignal(
                "PropertiesChanged",
                this._onPropertiesChanged.bind(this)
            );

            this._updateFromDBus();
            this._setSpotifyRunning(true);
        } catch (e) {
            global.logError("[SpotifyWidget] DBUS connect failed: " + e.message);
            this._setSpotifyRunning(false);
        }
    },

    _disconnectDBus: function() {
        if (this._propsProxy && this._propsSignalId) {
            this._propsProxy.disconnectSignal(this._propsSignalId);
            this._propsSignalId = 0;
        }
        this._playerProxy = null;
        this._propsProxy = null;
    },

    _setSpotifyRunning: function(running) {
        this._albumArt.visible = running && (this.showAlbumArt !== false);
        this._trackTitle.visible = running;
        this._trackArtist.visible = running;
        this._controlsBox.visible = running;
        this._progressContainer.visible = running;
        this._positionLabel.visible = running;
        this._volumeBox.visible = running;
        this._openButton.visible = running;
        this._statusLabel.visible = !running;
        this._launchButton.visible = !running;
    },

    // --- DBUS Signal Handling ---

    _onPropertiesChanged: function(proxy, sender, [iface, changed, invalidated]) {
        if (iface !== MPRIS_PLAYER_IFACE) return;

        if (changed.Metadata) {
            this._updateMetadata(changed.Metadata.deep_unpack());
        }
        if (changed.PlaybackStatus) {
            this._updatePlaybackStatus(changed.PlaybackStatus.deep_unpack());
        }
        if (changed.Volume) {
            this._updateVolume(changed.Volume.deep_unpack());
        }
    },

    _updateFromDBus: function() {
        if (!this._playerProxy) return;

        try {
            let metadata = this._playerProxy.Metadata;
            if (metadata) {
                this._updateMetadata(metadata);
            }

            let status = this._playerProxy.PlaybackStatus;
            if (status) {
                this._updatePlaybackStatus(status);
            }

            let volume = this._playerProxy.Volume;
            if (volume !== undefined) {
                this._updateVolume(volume);
            }

            this._setSpotifyRunning(true);
        } catch (e) {
            global.logError("[SpotifyWidget] Update failed: " + e.message);
            this._setSpotifyRunning(false);
        }
    },

    // --- Metadata Updates ---

    _updateMetadata: function(metadata) {
        // Title
        let title = this._getMetadataString(metadata, "xesam:title");
        this._trackTitle.set_text(title || "Unknown Track");

        // Artist
        let artists = this._getMetadataStringArray(metadata, "xesam:artist");
        this._trackArtist.set_text(artists || "Unknown Artist");

        // Track length
        let length = this._getMetadataInt64(metadata, "mpris:length");
        this._currentTrackLength = length;

        // Track ID (for SetPosition seek)
        this._currentTrackId = this._getMetadataString(metadata, "mpris:trackid");

        // Album art
        let artUrl = this._getMetadataString(metadata, "mpris:artUrl");
        this._updateAlbumArt(artUrl);
    },

    _getMetadataString: function(metadata, key) {
        if (metadata[key]) {
            let val = metadata[key];
            if (typeof val.deep_unpack === "function") {
                return val.deep_unpack();
            }
            return String(val);
        }
        return "";
    },

    _getMetadataStringArray: function(metadata, key) {
        if (metadata[key]) {
            let val = metadata[key];
            if (typeof val.deep_unpack === "function") {
                val = val.deep_unpack();
            }
            if (Array.isArray(val)) {
                return val.join(", ");
            }
            return String(val);
        }
        return "";
    },

    _getMetadataInt64: function(metadata, key) {
        if (metadata[key]) {
            let val = metadata[key];
            if (typeof val.deep_unpack === "function") {
                return val.deep_unpack();
            }
            return Number(val);
        }
        return 0;
    },

    _updateAlbumArt: function(artUrl) {
        if (!artUrl || !this.showAlbumArt) return;

        try {
            let isCompact = this.widgetSize === "compact";
            let size = isCompact ? 60 : 120;

            if (artUrl.startsWith("file://")) {
                let filePath = artUrl.substring(7);
                let file = Gio.File.new_for_path(filePath);
                if (file.query_exists(null)) {
                    let texture = St.TextureCache.get_default().load_uri_async(
                        artUrl, size, size
                    );
                    this._albumArt.set_child(texture);
                    return;
                }
            } else if (artUrl.startsWith("http")) {
                let texture = St.TextureCache.get_default().load_uri_async(
                    artUrl, size, size
                );
                this._albumArt.set_child(texture);
                return;
            }
        } catch (e) {
            global.logError("[SpotifyWidget] Album art failed: " + e.message);
        }

        // Fallback to icon
        this._albumArtIcon.set_icon_size(this.widgetSize === "compact" ? 60 : 120);
        this._albumArt.set_child(this._albumArtIcon);
    },

    // --- Playback Status ---

    _updatePlaybackStatus: function(status) {
        this._isPlaying = (status === "Playing");

        let iconName = this._isPlaying
            ? "media-playback-pause-symbolic"
            : "media-playback-start-symbolic";

        let icon = this._playPauseButton.get_child();
        if (icon) {
            icon.set_icon_name(iconName);
        }
    },

    // --- Position / Progress ---

    _startPositionPolling: function() {
        let interval = this.refreshInterval || 1000;
        this._positionTimerId = Mainloop.timeout_add(interval, () => {
            this._updatePosition();
            return GLib.SOURCE_CONTINUE;
        });
    },

    _stopPositionPolling: function() {
        if (this._positionTimerId) {
            Mainloop.source_remove(this._positionTimerId);
            this._positionTimerId = 0;
        }
    },

    _updatePosition: function() {
        if (!this._playerProxy) {
            // Try reconnecting
            this._connectDBus();
            return;
        }

        try {
            let position = this._playerProxy.Position;
            if (position !== undefined) {
                this._currentPosition = position;
                this._updateProgressBar();
                this._setSpotifyRunning(true);
            }
        } catch (e) {
            this._setSpotifyRunning(false);
            this._disconnectDBus();
        }
    },

    _updateProgressBar: function() {
        if (this._currentTrackLength <= 0) return;

        let fraction = this._currentPosition / this._currentTrackLength;
        fraction = Math.max(0, Math.min(1, fraction));

        let accent = this.accentColor || "rgba(30, 215, 96, 1.0)";
        let totalWidth = this._progressContainer.get_width();
        if (totalWidth > 0) {
            let fillWidth = Math.round(fraction * totalWidth);
            this._progressBar.set_style(
                `background-color: ${accent}; height: 4px; width: ${fillWidth}px;`
            );
            this._progressBg.set_style(
                `background-color: rgba(255,255,255,0.15); height: 4px; width: ${totalWidth - fillWidth}px;`
            );
        }

        // Position text
        let posStr = this._formatTime(this._currentPosition);
        let lenStr = this._formatTime(this._currentTrackLength);
        this._positionLabel.set_text(posStr + " / " + lenStr);
    },

    _formatTime: function(microseconds) {
        let totalSeconds = Math.floor(microseconds / 1000000);
        let minutes = Math.floor(totalSeconds / 60);
        let seconds = totalSeconds % 60;
        return minutes + ":" + (seconds < 10 ? "0" : "") + seconds;
    },

    // --- Playback Controls ---

    _onPlayPause: function() {
        if (!this._playerProxy) return;
        try {
            this._playerProxy.PlayPauseSync();
        } catch (e) {
            global.logError("[SpotifyWidget] PlayPause failed: " + e.message);
        }
    },

    _onNext: function() {
        if (!this._playerProxy) return;
        try {
            this._playerProxy.NextSync();
        } catch (e) {
            global.logError("[SpotifyWidget] Next failed: " + e.message);
        }
    },

    _onPrevious: function() {
        if (!this._playerProxy) return;
        try {
            this._playerProxy.PreviousSync();
        } catch (e) {
            global.logError("[SpotifyWidget] Previous failed: " + e.message);
        }
    },

    // --- Seek ---

    _onProgressClicked: function(actor, event) {
        if (!this._playerProxy || this._currentTrackLength <= 0) return;

        let [x] = event.get_coords();
        let [actorX] = actor.get_transformed_position();
        let actorWidth = actor.get_width();
        if (actorWidth <= 0) return;

        let fraction = Math.max(0, Math.min(1, (x - actorX) / actorWidth));
        let targetPosition = Math.floor(fraction * this._currentTrackLength);

        try {
            if (this._currentTrackId) {
                this._playerProxy.SetPositionSync(this._currentTrackId, targetPosition);
            } else {
                // Fallback: relative seek
                let offset = targetPosition - this._currentPosition;
                this._playerProxy.SeekSync(offset);
            }
            this._currentPosition = targetPosition;
            this._updateProgressBar();
        } catch (e) {
            global.logError("[SpotifyWidget] Seek failed: " + e.message);
        }
    },

    // --- Volume ---

    _updateVolume: function(volume) {
        this._currentVolume = Math.max(0, Math.min(1, volume));
        this._updateVolumeUI();
    },

    _updateVolumeUI: function() {
        let pct = Math.round(this._currentVolume * 100);
        this._volumeLabel.set_text(pct + "%");

        let totalWidth = this._volumeSliderContainer.get_width();
        if (totalWidth > 0) {
            let fillWidth = Math.round(this._currentVolume * totalWidth);
            let accent = this.accentColor || "rgba(30, 215, 96, 1.0)";
            this._volumeSliderFill.set_style(
                `background-color: ${accent}; height: 4px; width: ${fillWidth}px;`
            );
            this._volumeSliderBg.set_style(
                `background-color: rgba(255,255,255,0.15); height: 4px; width: ${totalWidth - fillWidth}px;`
            );
        }

        // Update icon
        let iconName;
        if (this._currentVolume <= 0) {
            iconName = "audio-volume-muted-symbolic";
        } else if (this._currentVolume < 0.33) {
            iconName = "audio-volume-low-symbolic";
        } else if (this._currentVolume < 0.66) {
            iconName = "audio-volume-medium-symbolic";
        } else {
            iconName = "audio-volume-high-symbolic";
        }
        this._volumeIcon.set_icon_name(iconName);
    },

    _onVolumeClicked: function(actor, event) {
        if (!this._playerProxy) return;

        let [x] = event.get_coords();
        let [actorX] = actor.get_transformed_position();
        let actorWidth = actor.get_width();
        if (actorWidth <= 0) return;

        let volume = Math.max(0, Math.min(1, (x - actorX) / actorWidth));
        this._setVolume(volume);
    },

    _onVolumeScroll: function(actor, event) {
        if (!this._playerProxy) return;

        let direction = event.get_scroll_direction();
        let step = 0.05;
        let volume = this._currentVolume;

        if (direction === Clutter.ScrollDirection.UP) {
            volume = Math.min(1, volume + step);
        } else if (direction === Clutter.ScrollDirection.DOWN) {
            volume = Math.max(0, volume - step);
        } else {
            return;
        }

        this._setVolume(volume);
    },

    _setVolume: function(volume) {
        try {
            this._playerProxy.Volume = volume;
            this._currentVolume = volume;
            this._updateVolumeUI();
        } catch (e) {
            global.logError("[SpotifyWidget] Volume set failed: " + e.message);
        }
    },

    // --- Window Management ---

    _onOpenSpotify: function() {
        let launcherPath = this._getLauncherPath();
        if (launcherPath) {
            Util.spawnCommandLine(launcherPath + " show");
        } else {
            Util.spawnCommandLine("wmctrl -a Spotify");
        }
    },

    _onLaunchSpotify: function() {
        let launcherPath = this._getLauncherPath();
        if (launcherPath) {
            Util.spawnCommandLine(launcherPath + " launch");
        } else {
            Util.spawnCommandLine("spotify");
        }

        // Retry DBUS connection after delay
        Mainloop.timeout_add(5000, () => {
            this._connectDBus();
            return GLib.SOURCE_REMOVE;
        });
    },

    _getLauncherPath: function() {
        // Check user setting first
        if (this.launcherPath) {
            return this.launcherPath;
        }

        // Auto-detect: look relative to desklet location
        let deskletDir = this._metadata.path;
        let candidates = [
            deskletDir + "/../../launcher/spotify-launcher.sh",
            GLib.get_home_dir() + "/.local/share/spotify-widget/spotify-launcher.sh",
            "/usr/local/bin/spotify-launcher.sh"
        ];

        for (let i = 0; i < candidates.length; i++) {
            let file = Gio.File.new_for_path(candidates[i]);
            if (file.query_exists(null)) {
                return candidates[i];
            }
        }

        return null;
    },

    // --- Lifecycle ---

    on_desklet_removed: function() {
        this._stopPositionPolling();
        this._disconnectDBus();
    }
};

function main(metadata, deskletId) {
    return new SpotifyWidget(metadata, deskletId);
}
