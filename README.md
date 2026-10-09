<div align="center">

# Notch Lyrics

**Time-synced, line-scrolling lyrics in your MacBook's notch.**

A fork of [Boring Notch](https://github.com/TheBoredTeam/boring.notch) that adds a
real lyrics pane and splits the open notch into player controls and lyrics — plus a
weather tab and a scratchpad that saves straight to Apple Notes.

[English](README.md) | [简体中文](README.zh-CN.md) | [Español](README.es.md)

<!-- Badges -->
[![License](https://img.shields.io/badge/license-GPL--3.0-blue.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-macOS%2014%2B-black.svg)](#requirements)
[![Fork of](https://img.shields.io/badge/fork%20of-TheBoredTeam%2Fboring.notch-orange.svg)](https://github.com/TheBoredTeam/boring.notch)
[![Release](https://img.shields.io/github/v/release/huo241/notch-lyrics?include_prereleases&sort=semver)](https://github.com/huo241/notch-lyrics/releases)
[![Downloads](https://img.shields.io/github/downloads/huo241/notch-lyrics/total)](https://github.com/huo241/notch-lyrics/releases)
[![Stars](https://img.shields.io/github/stars/huo241/notch-lyrics?style=flat)](https://github.com/huo241/notch-lyrics/stargazers)
[![Issues](https://img.shields.io/github/issues/huo241/notch-lyrics)](https://github.com/huo241/notch-lyrics/issues)

<!-- Quick buttons -->
[![Download](https://img.shields.io/badge/⬇%20Download-DMG-2ea44f?style=for-the-badge)](https://github.com/huo241/notch-lyrics/releases/latest)
[![Star](https://img.shields.io/badge/⭐%20Star-this%20repo-yellow?style=for-the-badge)](https://github.com/huo241/notch-lyrics/stargazers)
[![Report](https://img.shields.io/badge/🐞%20Report-an%20issue-red?style=for-the-badge)](https://github.com/huo241/notch-lyrics/issues)
[![Upstream](https://img.shields.io/badge/⬆%20Upstream-boring.notch-lightgrey?style=for-the-badge)](https://github.com/TheBoredTeam/boring.notch)

</div>

---

## Why this fork exists

Boring Notch has a lyrics toggle, but it only ever renders **a single line of
text** — the timing data was being thrown away before it reached the screen.
Turning it on got you one static line that swapped text as the song played.

This fork fixes the pipeline and the presentation:

| | Upstream | This fork |
|---|---|---|
| Lyrics display | One line, no scrolling | **5-line scrolling window, current line highlighted** |
| Timing source | Discarded | **LRC timestamps from LRCLIB** |
| Unsynced lyrics | Shown as plain text | Shown as a static block — **never fakes sync** |
| Lookup | `/api/search` only | **`/api/get` exact match, then `/api/search`** |
| Layout | Everything stacked on the left | **Player on the left, lyrics on the right** |
| Repeat requests | Re-fetched every time | **Cached per track** |
| Skipping tracks | Late response could overwrite the new song | **Guarded against** |

It also fixes a handful of upstream bugs found along the way — see
[Fixes carried here](#fixes-carried-here).

<div align="center">
  <img src="docs/assets/lyrics-demo.gif" alt="Notch Lyrics demo" width="720" />
</div>

## Features

Everything Boring Notch does, plus:

- 📜 **Scrolling lyrics** — the current line is highlighted, neighbours fade out
- 🎯 **Accurate sync** — driven by LRC timestamps, with `[offset:]`, multi-tag
  lines and word-level tags all handled
- 🧭 **Honest fallback** — when only unsynced lyrics exist you get a static,
  scrollable block instead of fake synchronisation, and it keeps trying to
  upgrade in the background
- 🪟 **Split layout** — player details on the left, lyrics on the right
- 🔁 **Per-track caching** — same song, no repeated network calls
- 🛡️ **Race-proof** — a previous track's late response can't overwrite the
  current one

### Beyond lyrics

Two more tabs, built to the same rules: one shared notch box, no layout surprises.

- 🌤️ **Weather tab** — current conditions, an hourly temperature curve and a 7-day
  strip, from [Open-Meteo](https://open-meteo.com) with **no API key required**.
  Search any city by name — `苏州市`, `Suzhou`, `Tokyo` all work — or leave it to
  automatic IP location. Geocoding runs on Photon (OSM), so counties and districts
  resolve as readily as big cities.
- ✍️ **Quick note** — a scratchpad inside the notch. Type, press Enter, and the text
  lands in an Apple Notes folder of your choice. Bold / italic / underline /
  strikethrough are supported, the draft survives the notch collapsing, and a failed
  write never eats your text — you get a retry instead.

<div align="center">
  <img src="docs/assets/weather-quicknote-demo.gif" alt="Weather tab and quick note" width="720" />
</div>

## Requirements

- **macOS 14 Sonoma** or later
- Apple Silicon or Intel Mac
- An internet connection for lyrics lookup (LRCLIB)

## Installation

### Download

Grab the latest `.dmg` from [**Releases**](https://github.com/huo241/notch-lyrics/releases/latest),
open it, and drag **Notch Lyrics** into `/Applications`.

### First launch

This build is **ad-hoc signed** (no Apple Developer account), so macOS will warn
you about an unidentified developer. Clear the quarantine flag once:

```bash
xattr -dr com.apple.quarantine "/Applications/Notch Lyrics.app"
```

Then open it normally.

> [!IMPORTANT]
> Because the signing identity differs from upstream, macOS treats this as a
> different app: **you will need to re-grant Accessibility, Automation and
> Calendar permissions** the first time you run it.

### Permissions worth granting

| Permission | What needs it |
|---|---|
| **Automation** (`Music`) | Favourite toggle, volume, play state |
| **Accessibility** | System HUD replacement |
| **Calendar / Reminders** | Calendar tab (optional) |
| **Camera** | Mirror (optional) |

## Usage

1. Launch the app — your notch becomes the control surface.
2. Hover the notch to expand it.
3. Play something in Apple Music or Spotify.
4. **The right-hand pane shows the lyrics**, scrolling and highlighting as the
   song plays.

### A note on lyrics sources

Time-synced lyrics come from [LRCLIB](https://lrclib.net). Two things are worth
knowing:

- **Apple Music's own lyrics are not usable.** AppleScript's `lyrics` property
  returns plain text only; the time-synced lines are rendered through a private
  API that scripts cannot reach. So even with Apple Music, sync depends on
  LRCLIB.
- **Media controller matters for artwork and the heart.** Set
  **Settings → Media Controller → Now Playing** for reliable artwork on
  streamed tracks and a working favourite button. The `Apple Music` mode talks
  to Music.app over AppleScript, which cannot read artwork from streaming
  (URL) tracks.

## Building from source

### Prerequisites

- **macOS 15.6** or later
- **Xcode 26** or later

### Steps

```bash
git clone https://github.com/huo241/notch-lyrics.git
cd notch-lyrics
open boringNotch.xcodeproj
```

Then press `Cmd + R`.

> [!NOTE]
> The project pulls 12 Swift Package dependencies. If `Resolve Package Graph`
> stalls, your network is likely the problem — see
> [TROUBLESHOOTING.md](TROUBLESHOOTING.md#build-fails-at-resolve-package-graph)
> for a workaround that sidesteps the network.

## Testing

```bash
xcodebuild build -project boringNotch.xcodeproj -scheme boringNotch \
  -configuration Release -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
```

The LRC parser (`boringNotch/helpers/LyricsParser.swift`) is dependency-free by
design so it can be exercised on its own:

```bash
swiftc -O boringNotch/helpers/LyricsParser.swift your_test.swift -o t && ./t
```

## Fixes carried here

Bugs found in upstream while working on lyrics, fixed in this fork:

| Fix | Symptom upstream |
|---|---|
| `AppleScriptHelper` now serialises scripts | `NSAppleScript` isn't thread-safe; concurrent calls threw or returned the *previous* call's result |
| Booleans read via `AppleScriptBoolean` | `favorited` returns `'true'`/`'fals'`, for which `booleanValue` is always `false` — the heart never lit up |
| Generation guard on favourite writes | A single tap started overlapping writes that fought each other |
| Intent guard on the heart | A stale read-back undid the tap, so the next tap inverted the wrong way |
| AppleScript runs with a 5-second timeout | One Apple Event that never got a reply blocked the serial script queue for good — every later script queued behind it and the panel froze |
| Playback state refreshes itself | After sleep/midnight, `com.apple.Music.playerInfo` silently stops delivering and nothing ever re-read state: tapping play did start the music, but the icon and lyrics stayed frozen on the old track |

## Differences from upstream

- App name is **Notch Lyrics**; the bundle identifier is unchanged, so existing
  preferences keep working.
- **Auto-update is disabled.** The upstream appcast ships builds without these
  changes, so updating against it would silently remove them. Re-enable it by
  setting `SUFeedURL` in `boringNotch/Info.plist` to your own feed.

## Roadmap

- [x] Time-synced scrolling lyrics
- [x] Split player / lyrics layout
- [x] Per-track lyrics cache
- [x] Weather tab with free-text city search
- [x] Quick note that files itself into Apple Notes
- [ ] Word-by-word (karaoke) highlighting
- [ ] User-adjustable lyric font and line count
- [ ] Offline lyrics cache

## Contributing

Issues and pull requests are welcome — please open them
[here](https://github.com/huo241/notch-lyrics/issues).

Since this is a fork, consider whether your change belongs
[upstream](https://github.com/TheBoredTeam/boring.notch) instead. Fixes that
aren't lyrics-specific are usually better contributed there.

See [CONTRIBUTING.md](CONTRIBUTING.md) for the upstream contribution guidelines.

## Acknowledgments

This project is a fork; the vast majority of the code is other people's work.

- **[The Bored Team](https://github.com/TheBoredTeam/boring.notch)** — the
  original Boring Notch and everything it does
- **[MediaRemoteAdapter](https://github.com/ungive/mediaremote-adapter)** — the
  Now Playing source on macOS 15.4+
- **[NotchDrop](https://github.com/Lakr233/NotchDrop)** — basis of the Shelf feature
- **[LRCLIB](https://lrclib.net)** — the lyrics database this fork depends on
- Icon credits: [@maxtron95](https://github.com/maxtron95)
- Website credits: [@himanshhhhuv](https://github.com/himanshhhhuv)

See [THIRD_PARTY_LICENSES](THIRD_PARTY_LICENSES) for the full list.

If you'd like to support the original project:
**[Ko-fi for the upstream author](https://www.ko-fi.com/alexander5015)**.

## License

**GPL-3.0**, same as upstream — see [LICENSE](LICENSE).

As required by the licence, this fork is distributed with its complete source
code and notes its modifications. If you redistribute it, keep the licence, the
source, and the attribution intact.
