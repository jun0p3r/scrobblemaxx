# Scrobblemaxx

A small menu-bar app for macOS that scrobbles what you play in Apple Music to your Last.fm profile.

> This app was generated with [Claude](https://claude.com/claude-code) (Anthropic's AI). It's a personal utility, so use it at your own risk.

## What it does
- Shows the current song over its album art, with a progress bar. The small line on the bar marks when the song will scrobble, and turns green once it has.
- Scrobbles to Last.fm automatically, and keeps scrobbles to send later if you're offline.
- Lets you fix wrong song info before or after it's scrobbled.
- Lets you choose when a song counts as played, and how the panel looks.

## Setup

**1. Install Apple's developer tools** (only needed once). Open Terminal and run:
```bash
xcode-select --install
```

**2. Download and build the app:**
```bash
git clone https://github.com/jun0p3r/scrobblemaxx.git
cd scrobblemaxx
./build.sh
open build/Scrobblemaxx.app
```
A music-note icon appears in your menu bar. You can drag `build/Scrobblemaxx.app` into your Applications folder if you like.

**3. Get a Last.fm API key** (free):
1. Go to https://www.last.fm/api/account/create and fill in the form. Any app name works, and you can leave the callback URL empty.
2. Keep the page open. You'll need the **API key** and **Shared secret**.

**4. Connect your account:**
1. Click the menu-bar icon, then the **⌃** button, then the gear (**Settings**).
2. In the **Account** tab, paste the API key and shared secret.
3. Click **Log In with Last.fm…**, approve it in your browser, then come back and click **Finish Login**.

**5. Play something in Music.** If macOS asks whether Scrobblemaxx can control Music, click **Allow**. This lets the app show the right playback time and album art.

That's it. To start the app automatically, turn on **Open at login** in Settings → General.

## Tips
- **Fixing a scrobble:** click **⌃**, then *Edit Current Track* or one of your recent scrobbles. Last.fm doesn't let apps edit scrobbles that were already sent. For those, Scrobblemaxx sends a corrected one and opens your Last.fm library so you can delete the old one.
- **The time looks wrong, or says "estimated":** the app isn't allowed to control Music. Turn it on in System Settings → Privacy & Security → Automation.
- **Hackintosh users:** if the "control Music" popup never appears, run `tools/grant-music-access.sh` once. Your Terminal needs Full Disk Access first.
