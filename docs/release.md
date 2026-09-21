# Releasing DKB Clamshell (native, macOS)

Everything runs locally on this Mac — no CI secrets, no GitHub Releases.
Same manual-publish model as DKB Monitor / DKB Downloader / DKB Secret:
build and sign here, upload by hand to admin.dangkhoabach.vn, and Sparkle
inside the installed app picks the new version up from
`updates.dangkhoabach.vn/dkb-clamshell/appcast.xml`.

No Apple Developer Program membership, so no Developer ID signing and no
notarization. Builds are signed with the self-signed **"DKB Clamshell Local
Signing"** certificate from `scripts/create-signing-cert.sh` (named in the
gitignored `Local.xcconfig`) — *not* ad-hoc like DKB Monitor / Downloader,
because macOS keys the Screen Recording grant on the signing identity: an
ad-hoc build gets a new identity every time, so every update would ask for
the permission again and the Full renderer would fall back to Lite until
it was granted. The certificate keeps the grant across releases (plan D1,
verified in Phase 0.4). On another Mac the first launch needs System
Settings › Privacy & Security › **Open Anyway**.

## One-time setup

1. **Signing certificate** — `scripts/create-signing-cert.sh` (creates the
   certificate in the login Keychain and writes `Local.xcconfig`).
2. **Sparkle EdDSA keypair** — already generated (2026-09-21) under the
   `dkb-clamshell` Keychain account, kept separate from DKB Monitor's
   (default `ed25519` account) and DKB Downloader's (`dkb-downloader`);
   `SUPublicEDKey` in `project.yml` is its public half. Only if it ever has
   to be regenerated:
   ```bash
   .sparkle-tools/2.6.4/bin/generate_keys --account dkb-clamshell
   ```
   `--account` is required — without it the tools fall back to the default
   account and silently reuse DKB Monitor's key.
3. **`create-dmg`** — `brew install create-dmg` (styles the installer's
   Finder window with an Applications drop link).

`project.yml` deliberately does not set `SUEnableAutomaticChecks` (same as
the other apps): Sparkle shows its own "check automatically?" prompt on the
second launch and stores the answer, which Settings › Updates reads and
writes. `AppDelegate` touches `AppUpdater.shared` at launch so the daily
scheduled check actually starts — the controller is lazy.

## Hardened Runtime and Sparkle

Release keeps Hardened Runtime (plan D14). Its library validation only
loads frameworks signed by Apple or by the app's own Team ID, and a
self-signed certificate has no Team ID — so the embedded
`Sparkle.framework`, although signed by the very same certificate, was
refused at launch ("mapping process and mapped file have different Team
IDs"). DKB Monitor / Downloader turn Hardened Runtime off for this reason;
this app instead adds the `com.apple.security.cs.disable-library-validation`
entitlement (`project.yml`), which lifts only that one check. `release.sh`
verifies the runtime flag and that exactly these two entitlements are
present (sandbox off, library validation off) and no `get-task-allow`.

## Cutting a release

```bash
./scripts/release.sh
```

Prompts for the version (Enter keeps the current one), writes it into both
`CFBundleShortVersionString` and `CFBundleVersion` in `project.yml` (the
source of truth — `Info.plist` is regenerated from it), then runs:
`swift test` (Core) → app tests → Release build with the local certificate
(universal arm64 + x86_64, temporary DerivedData) → verify signature,
Hardened Runtime, entitlements, architectures → DMG → Sparkle-sign under the
`dkb-clamshell` account. Output lands in `release-output/<version>/`
(gitignored): the `.dmg`, its `.sig` (raw EdDSA signature, ready to paste)
and the `.app` for `scripts/install-local.sh`.

The version must be `MAJOR.MINOR.PATCH` and not lower than the current one
(Sparkle would never offer a lower one). If anything fails after the
version was written, `project.yml` is restored.

The scheme builds its targets one after another (`parallelizeBuild: false`
in `project.yml`): with parallel builds the app's CodeSign raced the test
target copying its not-yet-signed `.xctest` into the app, and the app test
step failed with "code object is not signed at all. In subcomponent:
…DKBClamshellAppTests.xctest" — twice in a row, then not. If that message
ever comes back, that race is the first suspect.

## Uploading a release

Go to **admin.dangkhoabach.vn → Apps** and use "Publish new app" for the
first release (slug `dkb-clamshell`) or "Republish" afterwards, tick macOS
and upload:

| Form field | File |
|---|---|
| Installer file | `DKB-Clamshell-<version>.dmg` |
| Sparkle signature (.sig) | `DKB-Clamshell-<version>.dmg.sig` (paste its contents) |

Leave the Tauri-format "Updater bundle"/"Signature" fields empty. The admin
panel writes `updates.dangkhoabach.vn/dkb-clamshell/appcast.xml`, which
`SUFeedURL` in `project.yml` points at. Compare the SHA-256 the script
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
  after unlock (plan D11).
- The app never contacts the network except Sparkle's update check, and
  only when the user allowed automatic checks or asked for one.
