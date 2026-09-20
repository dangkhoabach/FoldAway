# DKB Clamshell

A menu-bar app for MacBooks that gives the built-in display an iPhone Duo-style
fold transition: as you lower the lid, the screen blurs, tilts toward the hinge
and fades to black in step with the hinge angle — driven by the lid angle
sensor, not a timer. After you open the lid and unlock, the content reveals
itself again.

The full design — measurements, decisions and the phase-by-phase checklist —
is in [`docs/dkb-clamshell-build-plan.md`](docs/dkb-clamshell-build-plan.md).

## Requirements

- macOS 14+.
- A MacBook with the lid angle sensor: MacBook Pro 16" (2019), MacBook Pro
  14"/16" (2021 and later), MacBook Air (M2, 2022 and later). The 13" MacBook
  Pro, the M1 MacBook Air and desktops don't have it; the app says so and does
  nothing.

## Two renderers

- **Lite** — works immediately, no permission: a system blur layer that fades
  in plus a darkening gradient.
- **Full** — the Duo look: the screen is captured for about a second while the
  lid moves and re-drawn with progressive blur, perspective toward the hinge
  and a fade to black. Needs the **Screen Recording** permission (macOS also
  re-confirms it periodically). Nothing captured is stored or sent anywhere.

`Auto` (default) uses Full when the permission is granted, Lite otherwise.

## Known limits

- macOS won't let any app draw over the Lock Screen, so the "open" direction
  only plays after you unlock.
- Only the built-in display is affected.

## Building

```bash
./scripts/create-signing-cert.sh   # once: self-signed identity → Local.xcconfig
xcodegen generate
open DKBClamshellNative.xcodeproj
```

Swift 6 / SwiftUI / AppKit, XcodeGen, no third-party dependencies.
