# Troubleshooting

## Build fails at `Resolve Package Graph`

**Symptom.** `xcodebuild` prints `Resolve Package Graph`, then hangs — sometimes
for many minutes — and eventually fails with messages like:

```
Failed to clone repository https://github.com/...:
    fatal: unable to access '...': Recv failure: Operation timed out
```

The project pulls 12 Swift Package dependencies. If your connection to GitHub is
slow or intermittent, resolution can stall or fail part-way through.

**What makes it worse.** When resolution fails, SPM may clear entries it had
already downloaded, so a retry does not necessarily start from where the last
one stopped.

### Workaround: fetch the dependencies yourself

`git clone` is often more reliable than SPM's own fetching. A bare repository
cloned by hand can be dropped straight into SPM's cache — the cache is just a
directory of bare repos named `<package>-<8 hex chars>`.

A shallow fetch of a single tag is far smaller and faster than a full clone, and
is enough because `Package.resolved` pins an exact revision:

```bash
git init --bare /tmp/dep.git
git -C /tmp/dep.git remote add origin https://github.com/<owner>/<repo>
git -C /tmp/dep.git fetch --quiet --depth 1 \
    origin "refs/tags/<version>:refs/tags/<version>"
```

Then place it where SPM expects it. The two locations are:

```bash
# SPM's shared cache
~/Library/Caches/org.swift.swiftpm/repositories/

# The project's own checkout area
~/Library/Developer/Xcode/DerivedData/<project>-<hash>/SourcePackages/repositories/
```

Both use the same `<name>-<suffix>` naming, so you can copy one into the other.
Read the exact names, versions and revisions from:

```
boringNotch.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved
```

> [!NOTE]
> A bare repo created this way has no `HEAD`. Set one, or SPM may not see it:
>
> ```bash
> tag=<version>
> printf 'ref: refs/tags/%s\n' "$tag" > /path/to/<name>-<suffix>/HEAD
> ```

Verify each entry before building:

```bash
for d in ~/Library/Caches/org.swift.swiftpm/repositories/*/; do
  printf '%-50s ' "$(basename "$d")"
  git --git-dir="$d" rev-parse --verify HEAD >/dev/null 2>&1 && echo OK || echo BROKEN
done
```

Then build again. With every dependency present locally, resolution no longer
needs the network.

### If it still stalls

`-disableAutomaticPackageResolution` makes `xcodebuild` use `Package.resolved`
as-is and process the local cache, printing `(cached)` per package instead of
re-fetching:

```bash
xcodebuild build -project boringNotch.xcodeproj -scheme boringNotch \
  -configuration Release -destination 'platform=macOS' \
  -disableAutomaticPackageResolution CODE_SIGNING_ALLOWED=NO
```

---

## The app builds but will not launch

**Symptom.** The process starts, then immediately exits, with dyld reporting:

```
Library not loaded: @rpath/MediaRemoteAdapter.framework/...
Reason: ... (non-platform) have different Team IDs
```

**Cause.** The bundled frameworks carry a code signature, and they must be
compatible with the host app's. This shows up when the app is signed ad-hoc
while a nested framework still carries a different signature.

**Fix.** Re-sign the bundle inside-out, then the app itself. Nested code must be
signed before whatever contains it.

```bash
APP="/Applications/Notch Lyrics.app"

# Nested components first, deepest last
for c in $(find "$APP/Contents" \
      \( -name "*.xpc" -o -name "*.app" -o -name "*.framework" \) \
      -maxdepth 5 | sort -r); do
  codesign --force --sign - "$c"
done

codesign --force --sign - "$APP"
```

> [!IMPORTANT]
> Signing the app without `--entitlements` **drops the sandbox and every
> permission it declares** (camera, calendar, Apple events). Extract the
> resolved entitlements from a build product first:
>
> ```bash
> codesign -d --entitlements /tmp/ents.plist \
>   "<DerivedData>/Build/Products/Release/Notch Lyrics.app"
> ```
>
> That output is not a normal plist; rebuild it as XML before passing it to
> `--entitlements`.

---

## The heart button lights up but nothing is favourited

Check **Settings → Media Controller**. In `Now Playing` mode the app asks
Music.app over AppleScript; in `Apple Music` mode it uses a different path.
Switching modes is usually the quickest test.

If it persists, note that macOS ties Automation permission to the app's signing
identity. Because this fork is signed differently from upstream, it is treated
as a **separate application** — open **System Settings → Privacy & Security →
Automation** and make sure Music is enabled for **Notch Lyrics**.

---

## Lyrics do not scroll

A static block instead of a moving list means **no timed lyrics were found** —
the app shows the plain text rather than pretending to stay in sync. This
happens when:

- LRCLIB has no record with timestamps for that track (common for obscure or
  very new releases), or
- the network lookup failed.

The app looks again in the background, so a track may gain scrolling lyrics a
moment after playback starts.

Note that **Apple Music's built-in lyrics cannot be used** for this: the
`lyrics` property AppleScript exposes is plain text only, and the timed lines
are drawn through a private API that scripts cannot reach.

---

## No artwork on streamed tracks

Use **Now Playing** rather than **Apple Music** as the media controller.
Artwork is read from Music.app over AppleScript in the latter mode, and
AppleScript cannot read artwork from streaming (URL) tracks — you will see the
app icon instead.
