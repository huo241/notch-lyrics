<div align="center">

<img src="docs/assets/icon.png" width="128" alt="Notch Lyrics icon">

# Notch Lyrics

**Time-synced lyrics, the weather, and a scratchpad — all in your MacBook's notch.**

A fork of [Boring Notch](https://github.com/TheBoredTeam/boring.notch) that adds a
real lyrics pane, a weather tab, and a quick note that files itself into Apple Notes.

> **This is a modified version of Boring Notch.** An independent fork, modified
> since **6 October 2026**. Not affiliated with or endorsed by The Bored Team.
> Released under GPL-3.0; what changed is listed in [NOTICE](NOTICE).

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

## What's new in 1.0

This is the release where the fork stopped being a fork. Upstream's name is gone
from the project, the bundle ID, the XPC helper and the CI; the lyric lookup was
rebuilt instead of patched; and the update channel is now this repository's own.
Full notes: [`docs/releases/1.0.0.md`](docs/releases/1.0.0.md).

| | |
|---|---|
| 🪪 **An identity of its own** | Project, targets, scheme, bundle ID and XPC helper renamed; every upstream reference stripped from CI, including the job that published to upstream's Homebrew tap. |
| 🔍 **Lyrics that were never missing** | LRCLIB's exact-match endpoint tolerates a **two-second** duration difference. The lookup falls back to a duration-free query and then to a locally scored search, with bracketed and dash-suffix noise stripped from the title first. |
| 🎯 **No more wrong matches** | Search results are scored against the playing track and everything below the threshold is rejected — showing nothing beats showing the wrong song. |
| ▶️ **The active line fills as it plays** | The current lyric wipes from dim to bright over its own duration, measured against the width of the text itself. |
| ✍️ **Quick notes: Notes or Obsidian** | The note panel picks its destination, and a chosen vault is remembered as a security-scoped bookmark — no new entitlement. |
| 🔄 **Its own update channel** | Sparkle checks this repository's feed and verifies it against a key generated for this project. |
| 🏷️ **A switch that lied** | The lyrics toggle said *"below artist name"*, a location that has not existed for a long time — it drives the pane on the right of the open notch. Renamed, and the Chinese catalogue finally has a real translation. |

### Inherited from upstream 2.8.0

Everything below came from boring.notch and is unchanged in this fork; it is
listed here because 1.0 is the first release this repository publishes.

| | |
|---|---|
| 🌤️ **Weather tab** | Current conditions, an hourly temperature curve with precipitation, and a 7-day strip. [Open-Meteo](https://open-meteo.com) data, **no API key**, search any city in any language, or let IP location do it. |
| ✍️ **Quick note** | A scratchpad in the notch with a formatting toolbar. Press Enter and the note lands in an Apple Notes folder you pick. |
| 🎵 **Playback state heals itself** | After sleep or a long idle stretch the panel used to freeze on the old track: play started music, but the icon and lyrics never moved. It now re-reads state on its own. |
| ⏱️ **AppleScript has a timeout** | One Apple Event that never answered used to block the serial script queue permanently — the whole panel froze with it. Scripts now give up after 5 seconds. |
| 🪟 **No more notch shadow** | Removed entirely, along with its setting. The shadow was composited offscreen on every animation frame, which made it flicker against the animated sky. |

## Three tabs, one notch

Same box, same size, no layout surprises — the notch is one shared surface and
each tab is a different face of it.

| Tab | What it is |
|---|---|
| 🎵 **Lyrics** | Player on the left, a 5-line scrolling lyrics window on the right |
| 🌤️ **Weather** | The sky, drawn in the notch, with an hourly curve and a week strip |
| ✍️ **Quick note** | A scratchpad that writes to Apple Notes |

### 🎵 Lyrics that actually scroll

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

Under the hood:

- 🎯 **Accurate sync** — driven by LRC timestamps, refreshed every 100 ms so a
  line change lands within ~100 ms of the beat. `[offset:]`, multi-tag lines and
  word-level tags are all handled.
- 🧭 **Honest fallback** — when only unsynced lyrics exist you get a static,
  scrollable block instead of fake synchronisation, and it keeps trying to
  upgrade in the background.
- 🔁 **Per-track caching** — same song, no repeated network calls.
- 🛡️ **Race-proof** — a previous track's late response can't overwrite the
  current one.

<div align="center">
  <img src="docs/assets/lyrics-demo.gif" alt="Notch Lyrics demo" width="720" />
</div>

### 🌤️ Weather, without an API key

- **Current conditions**, pulled from [Open-Meteo](https://open-meteo.com) —
  free and keyless.
- **Hourly curve** — temperature spline with precipitation-probability bars under it.
- **7-day strip** — per-day high/low with a daylight bar showing how much of the
  day the sun is up.
- **A live sky** — the backdrop's colours follow the weather code and whether
  it's day or night, so a rainy tab doesn't look like a sunny one. The animated
  backdrop can be switched off.
- **Search anywhere** — geocoding runs on [Photon](https://photon.komoot.io)
  (OpenStreetMap), so `苏州市`, `Suzhou`, `淳安县` and `Tokyo` all resolve;
  counties and districts work, not just capitals. A hand-picked city always wins
  over the automatic guess.
- **Location without prompts** — IP lookup by default (`ipwho.is`, with
  `ipinfo.io` as fallback) and the result is cached, so it doesn't re-geolocate
  on every launch.

### ✍️ A quick note that lands in Notes

- **Type and press Enter** — the text is written into an Apple Notes folder of
  your choosing. Pick the folder from inside the notch the first time; change it
  any time from the chip in the toolbar.
- **Formatting that survives** — bold / italic / underline / strikethrough, with
  the state of each shown on its button.
- **Your draft is never the view's problem** — the draft lives outside the tab,
  so collapsing the notch (hover-out, Esc, swipe, outside click) doesn't wipe
  what you were typing.
- **A failed write doesn't eat your text** — you get an error and a retry button,
  not silence.
- **Composition-safe** — CJK IME composition isn't flushed mid-word, so the first
  character of a Chinese word no longer disappears.

<div align="center">
  <img src="docs/assets/weather-quicknote-demo.gif" alt="Weather tab and quick note" width="720" />
</div>

## Requirements

- **macOS 14 Sonoma** or later
- Apple Silicon or Intel Mac
- An internet connection for lyrics lookup (LRCLIB) and weather (Open-Meteo)

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
| **Automation** (`Notes`) | Quick note — writing the note into your folder |
| **Accessibility** | System HUD replacement |
| **Calendar / Reminders** | Calendar tab (optional) |
| **Camera** | Mirror (optional) |

## Usage

1. Launch the app — your notch becomes the control surface.
2. Hover the notch to expand it.
3. Switch tabs in the header: **lyrics**, **weather**, **quick note**.
4. Play something in Apple Music or Spotify — **the right-hand pane shows the
   lyrics**, scrolling and highlighting as the song plays.

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
open NotchLyrics.xcodeproj
```

Then press `Cmd + R`.

> [!NOTE]
> The project pulls 12 Swift Package dependencies. If `Resolve Package Graph`
> stalls, your network is likely the problem — see
> [TROUBLESHOOTING.md](TROUBLESHOOTING.md#build-fails-at-resolve-package-graph)
> for a workaround that sidesteps the network.

## Testing

```bash
xcodebuild build -project NotchLyrics.xcodeproj -scheme NotchLyrics \
  -configuration Release -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
```

The LRC parser (`NotchLyrics/helpers/LyricsParser.swift`) is dependency-free by
design so it can be exercised on its own:

```bash
swiftc -O NotchLyrics/helpers/LyricsParser.swift your_test.swift -o t && ./t
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

- The app is **Notch Lyrics**, with its own bundle identifier
  (`blog.snappy.notchlyrics`). macOS treats it as a separate app, so settings
  from a Boring Notch install are not carried over.
- **Auto-update is enabled** and points at this repository's own signed feed
  (`updater/appcast.xml`); releases are published here, not upstream.
- The window-shadow experiment is gone for good — the window is back to its
  original width, and there is no shadow setting to fight with.

## Roadmap

- [x] Time-synced scrolling lyrics
- [x] Split player / lyrics layout
- [x] Per-track lyrics cache
- [x] Weather tab with free-text city search
- [x] Quick note that files itself into Apple Notes
- [x] Line-fill progress highlighting
- [ ] Word-by-word (karaoke) highlighting
- [ ] User-adjustable lyric font and line count
- [ ] Offline lyrics cache

## Contributing

Issues and pull requests are welcome — please open them
[here](https://github.com/huo241/notch-lyrics/issues). Where a change
belongs is described in [CONTRIBUTING.md](CONTRIBUTING.md).

## Acknowledgments

Notch Lyrics stands on the shoulders of these projects:

- **[The Bored Team](https://github.com/TheBoredTeam/boring.notch)** — the
  original Boring Notch, the foundation this project builds on
- **[MediaRemoteAdapter](https://github.com/ungive/mediaremote-adapter)** — the
  Now Playing source on macOS 15.4+
- **[NotchDrop](https://github.com/Lakr233/NotchDrop)** — basis of the Shelf feature
- **[LRCLIB](https://lrclib.net)** — the lyrics database this project depends on
- **[Open-Meteo](https://open-meteo.com)** — weather data, no key required
- **[Photon](https://photon.komoot.io)** (OpenStreetMap) — city geocoding

See [THIRD_PARTY_LICENSES](THIRD_PARTY_LICENSES) for the full list.

## License

**GPL-3.0** — see [LICENSE](LICENSE).

As required by the licence, this project is distributed with its complete
source code and notes its modifications. If you redistribute it, keep the
licence, the source, and the attribution intact.
