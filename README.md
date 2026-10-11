# Last.fm Scrobbler (menu bar)

A tiny macOS menu-bar app that scrobbles Apple Music to Last.fm.
AI WAS USED IN THIS PROJECT! INTENDED AS A PERSONAL UTILITY!

## Setup
1. Create a free API account at https://www.last.fm/api/account/create (the callback URL can be left blank) and note the **API key** and **shared secret**.
2. Build: `./build.sh` → produces `build/Last.fm Scrobbler.app`.
3. Run: `open "build/Last.fm Scrobbler.app"` (or drag it into /Applications).
4. Click the ♪ icon → **Settings…**, paste the key and secret, click **Log In with Last.fm…**, approve in the browser, then click **Finish Login**.

To start it at login: System Settings → General → Login Items → add the app.

## How it works
- Listens to Music.app's `com.apple.Music.playerInfo` notifications for track changes, and asks Music (via AppleScript) for the playback position and artwork. macOS shows a one-time "allow control of Music" prompt for this; if you decline, position is estimated and artwork comes from Last.fm / the iTunes Search API instead. The app never launches Music itself.
- The panel shows the current track over its blurred cover art, with a full-track progress bar. The tick on the bar marks the scrobble point (hover it to see the time) and turns green once the track is scrobbled.
- The ⌃ button opens a card with Edit, recent scrobbles, the scrobbling switch, Settings, your profile and Quit.
- **Settings** (General / Appearance / Account):
  - *Scrobble point*: 0–100% of the track in 1% steps (default 50%), optionally capped at 4 minutes. Below 50% works but goes against Last.fm's guidelines.
  - *Appearance*: show/hide the artwork background, automatic or manual dimming, and blur amount.
  - *Open at login*.
- If Music access is denied, the elapsed time is only an estimate and the panel shows a link to System Settings → Privacy & Security → Automation to turn it on.
- Sends "now playing" when a track starts, and scrobbles once it has *actually played* (pauses don't count) for half its length or 4 minutes, whichever comes first. Tracks ≤ 30 s are ignored.
- Failed scrobbles are queued in `~/Library/Application Support/LastfmScrobbler/queue.json` and retried every minute.
- **Editing:** open the ⌃ card and choose *Edit current track* or click a recent scrobble. Edits to the current or queued track change what gets sent; "Always apply this correction" remembers it for future plays (`corrections.json`). Last.fm's API can't edit sent scrobbles, so for those a corrected scrobble is sent with the original timestamp and your library page for that day opens so you can delete the wrong one.
- API key, secret and session key are stored in the Keychain. Since the app is ad-hoc signed, macOS may ask again for Keychain and Music access after each rebuild — choose **Always Allow**.
