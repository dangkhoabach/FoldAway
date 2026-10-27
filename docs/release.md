# Releasing FoldAway (native, macOS)

Everything runs locally on this Mac — no CI secrets, no GitHub Releases.
Same manual-publish model as DKB Monitor / DKB Downloader / DKB Secret:
build and sign here, upload by hand to admin.dangkhoabach.vn, and Sparkle
inside the installed app picks the new version up from
`updates.dangkhoabach.vn/dkb-clamshell/appcast.xml`.

No Apple Developer Program membership, so no Developer ID signing and no
notarization. Builds are signed with the self-signed **"FoldAway Local
Signing"** certificate from `scripts/create-signing-cert.sh` (named in the
gitignored `Local.xcconfig`) — *not* ad-hoc like DKB Monitor / Downloader,
because macOS keys the Screen Recording grant on the signing identity: an
ad-hoc build gets a new identity every time, so every update would ask for
the permission again and the Full renderer would fall back to Lite until
it was granted. The certificate keeps the grant across releases
(verified on a real install). On another Mac the first launch needs System
Settings › Privacy & Security › **Open Anyway**.

## One-time setup

1. **Signing certificate** — `scripts/create-signing-cert.sh` (creates the
   certificate in the login Keychain and writes `Local.xcconfig`).
2. **Sparkle EdDSA keypair** — already generated (2026-09-21) under the
   `dkb-clamshell` Keychain account, kept separate from DKB Monitor's
   (default `ed25519` account) and DKB Downloader's (`dkb-downloader`);
   `SUPublicEDKey` in `FoldAwayApp/Info.plist` is its public half. Only if it ever has
   to be regenerated:
   ```bash
   .sparkle-tools/2.6.4/bin/generate_keys --account dkb-clamshell
   ```
   `--account` is required — without it the tools fall back to the default
   account and silently reuse DKB Monitor's key.
3. **`create-dmg`** — `brew install create-dmg` (styles the installer's
   Finder window with an Applications drop link).

`Info.plist` deliberately does not set `SUEnableAutomaticChecks` (same as
the other apps): Sparkle shows its own "check automatically?" prompt on the
second launch and stores the answer, which Settings › Updates reads and
writes. `AppDelegate` touches `AppUpdater.shared` at launch so the daily
scheduled check actually starts — the controller is lazy.

## Hardened Runtime and Sparkle

Release keeps Hardened Runtime. Its library validation only
loads frameworks signed by Apple or by the app's own Team ID, and a
self-signed certificate has no Team ID — so the embedded
`Sparkle.framework`, although signed by the very same certificate, was
refused at launch ("mapping process and mapped file have different Team
IDs"). DKB Monitor / Downloader turn Hardened Runtime off for this reason;
this app instead adds the `com.apple.security.cs.disable-library-validation`
entitlement (`FoldAwayApp/FoldAwayApp.entitlements`), which lifts only that one check. `release.sh`
verifies the runtime flag and that exactly these two entitlements are
present (sandbox off, library validation off) and no `get-task-allow`.

## Cutting a release

```bash
./scripts/release.sh
```

Prompts for the version (Enter keeps the current one), writes it into both
`CFBundleShortVersionString` and `CFBundleVersion` in
`FoldAwayApp/Info.plist`, then runs:
`swift test` (Core) → app tests → Release build with the local certificate
(universal arm64 + x86_64, temporary DerivedData) → verify signature,
Hardened Runtime, entitlements, architectures → DMG → Sparkle-sign under the
`dkb-clamshell` account. Output lands in `release-output/<version>/`
(gitignored): the `.dmg`, its `.sig` (raw EdDSA signature, ready to paste)
and the `.app` for `scripts/install-local.sh`.

The version must be `MAJOR.MINOR.PATCH` and not lower than the current one
(Sparkle would never offer a lower one). If anything fails after the
version was written, `Info.plist` is restored.

The shared scheme (`FoldAway.xcodeproj/xcshareddata/xcschemes/
FoldAwayApp.xcscheme`, committed) builds its targets one after another
(`parallelizeBuildables = "NO"`; `DISABLE_MANUAL_TARGET_ORDER_BUILD_WARNING`
on the app target keeps Xcode's "manual order is deprecated" warning to a
verbose-only note): with parallel builds the app's CodeSign raced the test
target copying its not-yet-signed `.xctest` into the app, and the app test
step failed with "code object is not signed at all. In subcomponent:
…FoldAwayAppTests.xctest" — twice in a row, then not. If that message
ever comes back, that race is the first suspect.

## Build settings worth knowing

Set on the project/target in `FoldAway.xcodeproj` (open it in Xcode to change):

- `Local.xcconfig` is the base configuration of both build configurations and carries only
  `CODE_SIGN_IDENTITY`. Why: the Screen Recording grant (TCC) is keyed on the
  signing identity — ad-hoc would re-prompt after every rebuild; the self-signed certificate
  keeps it (verified on a real install). The build fails until the file exists, on purpose.
- `CODE_SIGN_STYLE = Manual`, no team: built and installed on this Mac only, no Apple
  Developer Program, nothing that can expire.
- `ENABLE_HARDENED_RUNTIME` is `YES` for Release only: Xcode 16+ Debug builds link
  the app through a generated `<App>.debug.dylib`, and Hardened Runtime's library validation
  rejects that dylib under a non-Apple identity — confirmed in DKB-Secret.
- `CODE_SIGN_INJECT_BASE_ENTITLEMENTS = NO` for Release: Xcode otherwise injects
  `get-task-allow` (debugger attach) into every Manual-signed build.
- **Sparkle is pinned to an exact version** (`2.10.0`) in the package reference, like DKB
  Monitor / Downloader: an open range would let a routine build move the update framework to
  an unreviewed release. The workspace's `Package.resolved` is committed too. Bumping is a
  deliberate edit that comes with re-reading Sparkle's release notes.
- `SWIFT_EMIT_LOC_STRINGS = YES`: the compiler must emit the exact runtime keys for
  interpolated SwiftUI strings, or hand-written catalog entries never match at runtime.
- Not sandboxed: IOKit HID access to the lid angle sensor and ScreenCaptureKit are
  simpler outside the sandbox, and the app holds nothing worth isolating; it makes no network
  calls of its own.
- `Info.plist`: `LSUIElement = true` (menu bar only) and
  `NSScreenCaptureUsageDescription` (shown the first time the Full renderer starts a
  ScreenCaptureKit stream).

## Uploading a release

Go to **admin.dangkhoabach.vn → Apps** and use "Publish new app" for the
first release (slug `dkb-clamshell`) or "Republish" afterwards, tick macOS
and upload:

| Form field | File |
|---|---|
| Installer file | `FoldAway-<version>.dmg` |
| Sparkle signature (.sig) | `FoldAway-<version>.dmg.sig` (paste its contents) |

Leave the Tauri-format "Updater bundle"/"Signature" fields empty. The admin
panel writes `updates.dangkhoabach.vn/dkb-clamshell/appcast.xml`, which
`SUFeedURL` in `Info.plist` points at. Compare the SHA-256 the script
printed with the uploaded file — the DMG and the signature are two separate
fields and a mismatch makes every client reject the update with an error
that points nowhere near the cause.

## Installing locally

```bash
./scripts/install-local.sh            # newest release-output/<version>
```

Copies the `.app` into `/Applications` and launches it. The Screen
Recording grant carries over from earlier builds signed with the same
certificate; if the certificate was ever recreated, grant it again in
System Settings › Privacy & Security › Screen & System Audio Recording.

## Limits worth remembering

- No app can draw on the Lock Screen, so the opening-lid effect only runs
  after unlock.
- The app never contacts the network except Sparkle's update check, and
  only when the user allowed automatic checks or asked for one.
