# Ujer

> Talk. Stop. Keep typing.

**Ujer** is a tiny, native macOS menu-bar app for turning spoken thoughts into text wherever your cursor already is.

Click the Ujer icon, talk, hit stop. Your audio is transcribed through the endpoint you configure, then inserted into the app you were using—Slack, Discord, Notes, Cursor, a browser, and more.

No account system. No Ujer backend. No history. No analytics.

## Why I made this

I wanted dictation that feels like a Mac utility, not another destination app. The note should land exactly where I was writing, then get out of the way.

Ujer records only while you explicitly start a session. While recording, it shows a small draggable HUD with a real microphone waveform: silence stays flat; speech draws the bars.

## What it does

- Lives in the menu bar and starts/stops with one click.
- Shows a draggable recording HUD with elapsed time, a real audio-level waveform, and a stop button.
- Records mono AAC audio locally, sends it to one OpenAI-compatible `POST /audio/transcriptions` endpoint, then deletes the temporary recording.
- Inserts the result into the focused text field through Accessibility, with a guarded clipboard fallback when direct insertion is unsupported.
- Lets you configure the base URL, model, and API token in the app.
- Stores the token in the macOS Keychain.
- Supports `https` endpoints and `http` only for loopback development servers.

## Quick start

Requirements: Apple Silicon, macOS 14+, Xcode 26.2.

```bash
git clone https://github.com/Azzamjiul/ujer.git
cd ujer
open Ujer.xcodeproj
```

Run the **Ujer** scheme in Xcode, then:

1. Open **Settings** from the menu-bar icon.
2. Set your OpenAI-compatible base URL, model, and token. The defaults are `https://api.openai.com/v1` and `gpt-transcribe`.
3. Grant Microphone and Accessibility access when macOS asks.
4. Left-click the Ujer icon to record. Drag the HUD wherever it feels right.

## Privacy and safety

Your token stays in Keychain. Audio exists only as a temporary `.m4a` file and is deleted on success, cancellation, and error.

Ujer checks the original target again before pasting. If the focus cannot be verified—such as after the app closes or the user changes windows—it does not paste blindly. The transcript remains in the clipboard instead.

## Build and test

```bash
xcodebuild test \
  -project Ujer.xcodeproj \
  -scheme Ujer \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO
```

`scripts/release.sh` contains the Developer ID archive, notarization, and DMG release sequence.

## What Ujer deliberately does not do

It has no cloud sync, analytics, updater, voice history, global shortcut, or provider picker. One small job: speak into the app you are already using.
