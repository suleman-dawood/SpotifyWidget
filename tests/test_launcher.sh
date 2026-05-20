#!/bin/bash
# test_launcher.sh — Unit tests for spotify-launcher.sh
#
# Tests the launcher script's functions in isolation using mocked commands.
# Run: bash tests/test_launcher.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
LAUNCHER="$PROJECT_DIR/launcher/spotify-launcher.sh"

PASS=0
FAIL=0
TESTS=0

# --- Test Helpers ---

assert_eq() {
    local desc="$1" expected="$2" actual="$3"
    TESTS=$((TESTS + 1))
    if [[ "$expected" == "$actual" ]]; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc"
        echo "    expected: '$expected'"
        echo "    actual:   '$actual'"
        FAIL=$((FAIL + 1))
    fi
}

assert_exit_code() {
    local desc="$1" expected="$2"
    shift 2
    TESTS=$((TESTS + 1))
    set +e
    "$@" >/dev/null 2>&1
    local actual=$?
    set -e
    if [[ "$expected" == "$actual" ]]; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc (exit code: expected $expected, got $actual)"
        FAIL=$((FAIL + 1))
    fi
}

assert_contains() {
    local desc="$1" needle="$2" haystack="$3"
    TESTS=$((TESTS + 1))
    if [[ "$haystack" == *"$needle"* ]]; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc"
        echo "    expected to contain: '$needle'"
        echo "    in: '$haystack'"
        FAIL=$((FAIL + 1))
    fi
}

# --- Tests ---

echo "=== Launcher Script Tests ==="
echo ""

# Test 1: Script exists and is executable
echo "--- File Tests ---"
assert_eq "launcher script exists" "true" "$(test -f "$LAUNCHER" && echo true || echo false)"
assert_eq "launcher script is executable" "true" "$(test -x "$LAUNCHER" && echo true || echo false)"

# Test 2: Invalid command shows usage
echo ""
echo "--- Usage Tests ---"
output=$(bash "$LAUNCHER" invalidcommand 2>&1 || true)
assert_contains "invalid command shows usage" "Usage:" "$output"

# Test 3: Status command works (Spotify not running in test env)
echo ""
echo "--- Status Tests ---"
output=$(bash "$LAUNCHER" status 2>&1)
# Status should report either "running" or "stopped" — both are valid
TESTS=$((TESTS + 1))
if [[ "$output" == "running" || "$output" == "stopped" ]]; then
    echo "  PASS: status reports valid state ($output)"
    PASS=$((PASS + 1))
else
    echo "  FAIL: status reports unexpected value: '$output'"
    FAIL=$((FAIL + 1))
fi

# Test 4: Script sources correctly (syntax check)
echo ""
echo "--- Syntax Tests ---"
assert_exit_code "launcher script has valid bash syntax" 0 bash -n "$LAUNCHER"

# Test 5: Install script syntax check
echo ""
echo "--- Install Script Tests ---"
assert_eq "install script exists" "true" "$(test -f "$PROJECT_DIR/launcher/install.sh" && echo true || echo false)"
assert_eq "install script is executable" "true" "$(test -x "$PROJECT_DIR/launcher/install.sh" && echo true || echo false)"
assert_exit_code "install script has valid bash syntax" 0 bash -n "$PROJECT_DIR/launcher/install.sh"

# Test 6: Launch command fails gracefully without dependencies
echo ""
echo "--- Dependency Check Tests ---"
output=$(SPOTIFY_ADBLOCK_LIB="/nonexistent/path.so" bash "$LAUNCHER" launch 2>&1 || true)
assert_contains "launch fails with missing deps" "Missing dependencies" "$output"

# --- Desklet File Tests ---
echo ""
echo "=== Desklet File Tests ==="

DESKLET_DIR="$PROJECT_DIR/desklet/spotify-widget@suleman"

echo ""
echo "--- Required Files ---"
assert_eq "metadata.json exists" "true" "$(test -f "$DESKLET_DIR/metadata.json" && echo true || echo false)"
assert_eq "desklet.js exists" "true" "$(test -f "$DESKLET_DIR/desklet.js" && echo true || echo false)"
assert_eq "settings-schema.json exists" "true" "$(test -f "$DESKLET_DIR/settings-schema.json" && echo true || echo false)"
assert_eq "stylesheet.css exists" "true" "$(test -f "$DESKLET_DIR/stylesheet.css" && echo true || echo false)"

# Test metadata.json structure
echo ""
echo "--- metadata.json Validation ---"
if command -v python3 >/dev/null 2>&1; then
    meta_valid=$(python3 -c "
import json, sys
with open('$DESKLET_DIR/metadata.json') as f:
    data = json.load(f)
    required = ['uuid', 'name', 'description', 'version']
    missing = [k for k in required if k not in data]
    if missing:
        print('missing: ' + ', '.join(missing))
        sys.exit(1)
    if data['uuid'] != 'spotify-widget@suleman':
        print('wrong uuid: ' + data['uuid'])
        sys.exit(1)
    print('valid')
" 2>&1)
    assert_eq "metadata.json has required fields" "valid" "$meta_valid"
fi

# Test settings-schema.json structure
echo ""
echo "--- settings-schema.json Validation ---"
if command -v python3 >/dev/null 2>&1; then
    settings_valid=$(python3 -c "
import json, sys
with open('$DESKLET_DIR/settings-schema.json') as f:
    data = json.load(f)
    required_keys = ['background-color', 'font-color', 'accent-color', 'font-scale',
                     'show-album-art', 'widget-size', 'refresh-interval', 'launcher-path']
    missing = [k for k in required_keys if k not in data]
    if missing:
        print('missing: ' + ', '.join(missing))
        sys.exit(1)
    # Check each key has type and default
    for key in required_keys:
        if 'type' not in data[key]:
            print(f'{key} missing type')
            sys.exit(1)
        if 'default' not in data[key]:
            print(f'{key} missing default')
            sys.exit(1)
    print('valid')
" 2>&1)
    assert_eq "settings-schema.json has all keys with type+default" "valid" "$settings_valid"
fi

# Test desklet.js has required exports
echo ""
echo "--- desklet.js Structure ---"
assert_contains "desklet.js exports main function" "function main" "$(cat "$DESKLET_DIR/desklet.js")"
assert_contains "desklet.js has SpotifyWidget constructor" "function SpotifyWidget" "$(cat "$DESKLET_DIR/desklet.js")"
assert_contains "desklet.js has MPRIS bus name" "org.mpris.MediaPlayer2.spotify" "$(cat "$DESKLET_DIR/desklet.js")"
assert_contains "desklet.js has PlayPause method" "PlayPause" "$(cat "$DESKLET_DIR/desklet.js")"
assert_contains "desklet.js has Next method" "Next" "$(cat "$DESKLET_DIR/desklet.js")"
assert_contains "desklet.js has Previous method" "Previous" "$(cat "$DESKLET_DIR/desklet.js")"
assert_contains "desklet.js has PropertiesChanged handler" "PropertiesChanged" "$(cat "$DESKLET_DIR/desklet.js")"
assert_contains "desklet.js has on_desklet_removed cleanup" "on_desklet_removed" "$(cat "$DESKLET_DIR/desklet.js")"

# Phase 2: Seek, Volume
echo ""
echo "--- Phase 2: Seek + Volume ---"
DESKLET_JS="$(cat "$DESKLET_DIR/desklet.js")"
assert_contains "desklet.js has seek handler" "_onProgressClicked" "$DESKLET_JS"
assert_contains "desklet.js has SetPosition for seek" "SetPositionSync" "$DESKLET_JS"
assert_contains "desklet.js has Seek fallback" "SeekSync" "$DESKLET_JS"
assert_contains "desklet.js has volume click handler" "_onVolumeClicked" "$DESKLET_JS"
assert_contains "desklet.js has volume scroll handler" "_onVolumeScroll" "$DESKLET_JS"
assert_contains "desklet.js has volume UI updater" "_updateVolumeUI" "$DESKLET_JS"
assert_contains "desklet.js has trackId for seek" "_currentTrackId" "$DESKLET_JS"
assert_contains "desklet.js tracks Volume in PropertiesChanged" "changed.Volume" "$DESKLET_JS"

# Stylesheet has volume styles
STYLESHEET="$(cat "$DESKLET_DIR/stylesheet.css")"
assert_contains "stylesheet has volume-popup" "volume-popup" "$STYLESHEET"
assert_contains "stylesheet has volume-slider-container" "volume-slider-container" "$STYLESHEET"
assert_contains "stylesheet has progress hover" "progress-container:hover" "$STYLESHEET"

# UI layout tests
echo ""
echo "--- UI Layout ---"
assert_contains "desklet.js has horizontal top row" "_topRow" "$DESKLET_JS"
assert_contains "desklet.js has info column" "_infoColumn" "$DESKLET_JS"
assert_contains "desklet.js has elapsed time label" "_elapsedLabel" "$DESKLET_JS"
assert_contains "desklet.js has remaining time label" "_remainingLabel" "$DESKLET_JS"
assert_contains "stylesheet has top-row layout" "top-row" "$STYLESHEET"
assert_contains "stylesheet has info-column" "info-column" "$STYLESHEET"

# Test autostart desktop entry
echo ""
echo "=== Autostart Entry Tests ==="
DESKTOP_FILE="$PROJECT_DIR/autostart/spotify-widget.desktop"
assert_eq "desktop file exists" "true" "$(test -f "$DESKTOP_FILE" && echo true || echo false)"

if command -v python3 >/dev/null 2>&1; then
    desktop_valid=$(python3 -c "
import sys
required = {'Type', 'Name', 'Exec'}
found = set()
with open('$DESKTOP_FILE') as f:
    for line in f:
        key = line.split('=')[0].strip()
        if key in required:
            found.add(key)
missing = required - found
if missing:
    print('missing: ' + ', '.join(missing))
    sys.exit(1)
print('valid')
" 2>&1)
    assert_eq "desktop file has required keys" "valid" "$desktop_valid"
fi

# --- Summary ---
echo ""
echo "================================"
echo "Results: $PASS passed, $FAIL failed, $TESTS total"
echo "================================"

if [[ $FAIL -gt 0 ]]; then
    exit 1
fi
