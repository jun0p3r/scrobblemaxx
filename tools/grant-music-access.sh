#!/bin/bash
# Grants "Scrobblemaxx" permission to control Music (Privacy & Security → Automation)
# by writing the same record macOS creates when you click "Allow" on the prompt.
#
# Only needed on Macs where macOS never shows that prompt, e.g. Hackintosh/OCLP setups booted
# with `amfi_get_out_of_my_way=0x1`: every app is then treated as a platform binary and TCC's
# policy refuses to prompt for non-Apple-signed ones. On a normal Mac, just click Allow instead.
#
# Requirements: the Terminal app you run this from needs Full Disk Access
# (System Settings → Privacy & Security → Full Disk Access).
# To undo: turn the switch off in System Settings → Privacy & Security → Automation,
# or run `tccutil reset AppleEvents com.fr.LastfmScrobbler`.
set -euo pipefail

DB="$HOME/Library/Application Support/com.apple.TCC/TCC.db"
APP_ID="com.fr.LastfmScrobbler"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Code requirements: the app is matched by bundle identifier (build.sh signs it that way),
# Music by Apple's own designated requirement.
csreq -r="identifier \"$APP_ID\"" -b "$TMP/client.bin"
csreq -r='identifier "com.apple.Music" and anchor apple' -b "$TMP/music.bin"
CLIENT_REQ="$(xxd -p "$TMP/client.bin" | tr -d '\n')"
MUSIC_REQ="$(xxd -p "$TMP/music.bin" | tr -d '\n')"

if ! sqlite3 "$DB" "INSERT OR REPLACE INTO access
      (service, client, client_type, auth_value, auth_reason, auth_version, csreq,
       indirect_object_identifier_type, indirect_object_identifier, indirect_object_code_identity, flags)
    VALUES
      ('kTCCServiceAppleEvents', '$APP_ID', 0, 2, 3, 1, X'$CLIENT_REQ',
       0, 'com.apple.Music', X'$MUSIC_REQ', 0);"; then
    echo
    echo "Couldn't write to the privacy database. Give your Terminal app Full Disk Access"
    echo "(System Settings → Privacy & Security → Full Disk Access), reopen it, and run this again."
    exit 1
fi

# Make the privacy daemon re-read the database.
killall tccd 2>/dev/null || true

echo "Done: Scrobblemaxx may now control Music."
echo "Restart the app:  pkill -x Scrobblemaxx; open \"$(cd "$(dirname "$0")/.." && pwd)/build/Scrobblemaxx.app\""
