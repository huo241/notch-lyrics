# Contributing

Thank you for taking the time to contribute! ❤️

These guidelines help streamline the contribution process. By following them, you'll make
it easier to review your work and collaborate effectively.

## This is a fork — where does your change belong?

Notch Lyrics is a fork of [Boring Notch](https://github.com/TheBoredTeam/boring.notch).
Before you start, decide which repository should receive your change:

- **Fixes or features for what this fork adds** — the lyrics panel, the weather page, the
  quick-note board (Notes / Obsidian), or the Notch Lyrics visual identity → send it
  **here**, to [`huo241/notch-lyrics`](https://github.com/huo241/notch-lyrics).
- **Anything else** — the media player, calendar, notch window, gestures, build system,
  or any upstream feature → send it to
  [**upstream**](https://github.com/TheBoredTeam/boring.notch) instead. Fixes made there
  flow back into this fork when we rebase, and they have the user base to test them
  properly.

If you are not sure, open an issue here first and we will point you the right way.

## Table of Contents

- [Ways to Contribute](#ways-to-contribute)
- [Contributing Code](#contributing-code)
- [Translations](#translations)
- [Reporting Bugs](#reporting-bugs)
- [Feature Requests](#feature-requests)
- [Licence](#licence)

## Ways to Contribute

Writing code, improving documentation, reporting bugs, requesting features, translating
strings, or writing tutorials and blog posts. Every contribution, large or small, helps.

## Contributing Code

### Before You Start

- **Search existing issues** first, to avoid duplicates.
- **Discuss major changes**: for significant features, open an issue and describe your
  approach before writing code. It is much cheaper to agree on a design than to rework a
  pull request.

### Setting Up Your Environment

1. **Fork** [`huo241/notch-lyrics`](https://github.com/huo241/notch-lyrics) on GitHub.

2. **Clone your fork**:

   ```bash
   git clone https://github.com/{your-username}/notch-lyrics.git
   cd notch-lyrics
   ```

   Replace `{your-username}` with your GitHub username.

3. **Build it**: open `NotchLyrics.xcodeproj` in Xcode 16 or newer, or from the terminal:

   ```bash
   xcodebuild build -project NotchLyrics.xcodeproj -scheme NotchLyrics
   ```

   Requires macOS 14 or newer. The default branch is `main` — base your work on it.

4. **Create a branch**:

   ```bash
   git checkout -b feature/{your-feature-name}
   ```

   Use lowercase letters, numbers, and hyphens only (for example
   `feature/spotify-lyrics-offset` or `fix/note-save-crash`).

### Making Changes

1. Implement your change, following the conventions already used in the file you touch.
2. Build and run it. A change that does not compile will not be reviewed.
3. Commit with a message that explains **what** changed and **why**:

   ```bash
   git add .
   git commit -m "Describe the change"
   ```

4. Keep your branch up to date with `main`.

### Pull Requests

Open a pull request against `main` of this repository. A good description includes:

- a clear title summarising the change;
- what changed and why;
- any related issues (for example, "Fixes #12");
- screenshots or a short recording for anything visible in the UI.

Then respond to review feedback. Reviews may take a little time — thank you for your
patience.

## Translations

Strings live in `NotchLyrics/Localizable.xcstrings`, a String Catalog. This fork does
**not** use Crowdin and does not sync translations from any external service: add or fix
translations directly in the catalog as part of your pull request.

Chinese (Simplified) is the language the fork's own strings are written in first, so if
you add a new user-visible string, please fill in both English and Simplified Chinese.

## Reporting Bugs

Please include:

- a clear, descriptive title;
- steps to reproduce;
- expected behaviour versus what actually happened;
- screenshots or error messages where relevant;
- your environment: macOS version, app version, and whether it is a release build or one
  you built yourself.

## Feature Requests

Feature requests are welcome. Check whether it has already been requested, describe the
use case, explain why it would be valuable, and stay open to alternative approaches.

## Licence

Notch Lyrics is distributed under the **GPL-3.0**, the same licence as the project it is
based on. By contributing, you agree that your changes are licensed under the same terms.

---

Thank you for contributing! 🎉
