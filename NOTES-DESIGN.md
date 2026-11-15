# NOTES — DESIGN

> Superseded in part: the app was re-skinned from the dark v1 theme to the light "Daylight" direction (`DESIGN-V2.md`). The notes below on dark mode, ember gradients, glows, frosted surfaces, particles, radii and the asset list describe v1; see `NOTES-reskin.md` for what replaced them. The notes on naming (`DateClockView`), haptics, images and the app name still hold.

Decisions made where SPEC.md was silent. API reference: `ios/DESIGN-API.md`.

- **No Swift compiler here.** All 23 files parse cleanly with tree-sitter-swift, and every component call site was cross-checked against its initializer by script. Nothing has been type-checked by `swiftc`; first Xcode build may surface small fixes.
- **Asset catalog**: color sets `ink, plum, plumHi, ivory, mint, ash, amber, gold` as named in the spec, plus `emberStart, emberMid, emberEnd, danger, goldShade, AccentColor` (= emberMid). Regenerate with `python3 ios/Tools/generate_assets.py` (numpy + Pillow). The `mint` set shares a name with SwiftUI's system `Color.mint`; the design system only reads it by string name. If Xcode's generated asset symbols ever cause an ambiguity, set `ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS = NO` in project.yml.
- **App icon**: single 1024 px universal icon, RGB without alpha (`AppIcon.appiconset/AppIcon-1024.png`).
- **Dark only**: the design system does not force a color scheme globally; RootView should apply `.preferredColorScheme(.dark)`. Frosted surfaces force dark material themselves.
- **App name**: never hardcoded in components. `PaywallHero(eyebrow:)` takes it from the caller.
- **Primary button text is ink on ember** (not white): white on the ember gradient fails 4.5:1.
- **Verdict "sealed" state is identical for Yes and No**, so the screen never reveals the answer to someone glancing at it.
- **Turn card radius is 28** (between card 20 and sheet 32) because it reads as a docked sheet. "Pass" is an ivory pill, keeping ember for the clock bar.
- **Extras beyond the brief** (needed by screens): `ScreenHeader`, `TempoRow`, `TempoDivider`, `SliderRow` (max distance), `FlowLayout` (chip wrapping), `TempoRemoteImage`, `TempoSwitch`, `InterlockingRings`, `EmberParticles`, `TempoButton` (convenience over `TempoButtonStyle`).
- **`DateClockView`, not `DateClock`**: the brief asked for a view called `DateClock`, but Core defines `enum DateClock` (and `Core/Stores/DateClock.swift`). Two types and two files with the same name in one module will not build, so the design-system view and file are `DateClockView`.
- **PulseOrb** has optional `foundPhoto` / `foundName` so the orb can bloom into the partner, and draws its own caption line.
- **NextCountdown** has an optional `onFinished` callback; the store remains the authority on when the next search starts.
- **Images** use `AsyncImage` (so `URLCache.shared`); CORE may want to raise the shared cache's capacity at launch.
- **Haptics** live inside components (`sensoryFeedback`); screens should not add a second haptic for the same event.
