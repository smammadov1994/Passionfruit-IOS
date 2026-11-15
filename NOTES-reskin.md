# NOTES — re-skin to "Daylight" (DESIGN-V2.md)

Scope: `ios/` only. The native app was converted from the dark v1 theme to the light direction in
`DESIGN-V2.md`, plus one safety fix in Core. Nothing here has been compiled (no Swift toolchain);
see "Verification". API reference: `ios/DESIGN-API.md` (rewritten). `NOTES-DESIGN.md` describes v1
and now carries a pointer here.

## What changed

**Tokens and assets**
- `Tools/generate_assets.py` rewritten: 24 color sets, one universal value each (no dark variant);
  it deletes color sets that are no longer tokens. New sets: `hairline, textSecondary, textTertiary,
  ember, accentText, accentSoft, mintSoft, amberSoft, goldSoft, pastelBlush/Sage/Butter/Sky/Lilac`.
  Removed: `emberStart, emberMid, emberEnd, goldShade`.
- App icon regenerated: white, two thin interlocked vermilion rings, flat.
- `TempoColors`: v1 names kept (`ink` = white, `plum` = surface, `plumHi` = surface 2, `ivory` =
  near-black, `ember` = accent) with role aliases (`background, surface, surface2, textPrimary,
  accent, onAccent, yes/yesSoft, no/noSoft, warning/warningSoft, premium/premiumSoft, dangerSoft`).
  Features were moved to the aliases. `TempoTone` gained `textColor` and `soft`; new `TempoPastel`.
- `TempoGradient`: only flat fills remain (`ember, amber, gold, ash, flat(_:)`) and the video scrim
  (black, capped at 35%). Meshes, `innerHighlight`, angular/horizontal ember and `goldSheen` are gone.
- Type: serif medium, 44/44/40/34/28/24/20; eyebrow 12 +0.8; numerals SF Pro semibold monospaced
  (`TempoTextStyle.rounded` → `numerals`, `Font.tempo.rounded` → `numerals`); new `.tabLabel`.
- Radii 10/12/16/28, large button 54. One shadow: `TempoShadow.floating` (+ `.none`); `.card`,
  `.knob` and all glow modifiers removed. `tempoFrosted` → `tempoSurface(in:fill:isFloating:showsBorder:)`;
  new `tempoBottomSheet()`. Motion quieter: `bloom` → `settle`, `tempoReplace` is a fade + 8 pt slide.
- `project.yml`: `UIUserInterfaceStyle: Light`. `RootView`, `TempoApp`, previews: `.light`.

**Components** (all re-styled; signatures kept unless listed under "API changes")
`InkBackground` (plain white), buttons (black primary, outlined secondary, text ghost, outlined
destructive, black premium), `IconCircleButton`, chips, `TempoCard`, rows, text field, switch,
segmented picker, sliders, `AvatarView` (pastel + serif monogram), feedback, `PulseOrb`,
`DateClockView`, `NextCountdown`, `TurnCard`, `VerdictPad`, `MatchCelebration`, `SelfViewPiP`,
`CallControlBar`, `VideoScrim`, `ModerationWarningBanner`, paywall pieces, `LockedRow`,
`OnboardingProgress`, `PhotoSlot`, `MessageBubble`, `ChatComposer`, `DesignGallery`.
New: `IconTile`, `TempoPastel`, `TempoTextButton`, `LiveCountLine`, `FloatingCapsule`.

**Screens**
- Tab bar: white, hairline, outlined icon + label, filled icon + accent dot when selected
  (`AppTab.selectedSystemImage`; icons are now `moon`, `heart`, `person`).
- Tonight: left-aligned serif "Tonight" + live count line, allowance pill top right, the Pulse, guidance left-aligned.
- Welcome: interlocked rings as the mark; Apple button `.black` (or `.whiteOutline` beside the demo button).
- Onboarding: thin black progress line across the top, Back below it; icon-tile points; solid white footer.
- You / account / rules / paywall: icon-tile rows in white outlined cards; paywall left-aligned with a cream price card.
- Date flow: lobby on white; live chrome is white floating pieces; Verdict is a white bottom sheet over the
  blurred video under a 70% white veil; match, no-match, limit, suspended, call ringing/ended are
  left-aligned white screens. `CallPartnerLabel` is now a white card (it was bare text on video).
- Status bar is hidden over live video (`.statusBarHidden`) because light-mode status text is dark.
- Core visuals: `PlaceholderVideoUIView` (demo "video") is a muted sand / grey-blue drift, no brand
  color, no glow layer; video container background is surface 2.

**Safety fix (Core)**
- The cameras stay on through `.deciding` and `.awaitingResult`, so camera-frame sampling and frame
  moderation now continue until the video is torn down. `quietCallMedia()` only silences audio and
  calls the new `ModerationService.stopTranscription()`; `finishCallMedia()` still stops everything.
- So that a flag in those phases is acted on: `handleEnded` accepts `date.ended{moderation}` for all
  of `isInDate` (and cancels the decision/result timers), and `applyModeration` is guarded by
  `isInDate` instead of `isInCall`. The server already accepts frames until the session is `done`
  and ends the date for both (`server/src/realtime/DateEngine.ts`); the server was not changed.
- Mocks: `MockModerationService` tracks `isTranscribing` and `submittedFrameCount`;
  `MockVideoCallService` tracks `isSamplingFrames` and has `emitFrameSample(_:)`.
- Tests: `testVideoStaysUpSilencedThroughTheDecision` updated (frames flow while deciding and sealed,
  transcripts stop, everything stops at the result); new `testModerationCanEndTheDateWhileDeciding`.
- `CORE-API.md` updated. `NOTES-integration.md` item 1 still says sampling stops at the timer; that
  sentence is now out of date.

## API changes (call sites updated)

| Was | Now |
|---|---|
| `InkBackground(glow:showsGrain:)`, `.inkBackground(_:)`, `InkGlow` | `InkBackground()`, `.inkBackground()` |
| `tempoFrosted(in:tintOpacity:showsBorder:)` | `tempoSurface(in:fill:isFloating:showsBorder:)` |
| `emberGlow`, `goldGlow`, `tempoGlow`, `EmberParticles`, mesh gradients | removed |
| `FrostedCapsule` | `FloatingCapsule` |
| `TempoCardKind.frosted`, `IconCircleButtonKind.frosted` | `.floating` (+ `IconCircleButtonKind.outlined`) |
| `Color.tempo.emberStart/emberMid/emberEnd/goldShade/emberStops/goldStops` | `Color.tempo.accent` / `.premium` |
| `Animation.tempo.bloom` | `Animation.tempo.settle` |
| `TempoTextStyle.rounded(_:)`, `Font.tempo.rounded(_:)` | `numerals(_:)` |

Added, with defaults (old call sites compile): `TempoRow(tile:)`, `TempoToggleRow(tile:)`,
`LockedRow(tile:)`, `BenefitRow(tint:)`, `PulseOrb(showsOnlineCount:)`, `OnboardingPoint(tint:)`,
`FieldSection(systemImage:tile:)`, `DateFlowErrorBanner(isOverVideo:)`. `PulseOrb` default diameter 240 → 220.

## Decisions where DESIGN-V2 was silent

- **Selected states are black, not accent** (switch, slider fill, segmented pill), to match the
  black chips and keep the accent rare.
- **Small colored text.** Only accent-dark `#C8431F` and danger pass 4.5:1 on white. Mint (4.3),
  amber (4.0) and ochre (3.9) do not, so their small text is near-black and the tone is carried by
  an icon or a soft tint (`Chip`, `IconTile(tone:)`, `PremiumBadge`). Colored eyebrows were removed.
  The clock's amber digits are 17 pt semibold, which counts as large text.
- **Premium button** is black like primary (the doc asks for a black CTA); an icon in it is cream.
- **`hairlineStrong`** is near-black at 24% (chip outlines); no new hue was added.
- **Card kinds**: `raised` = surface + hairline for fields and notes; lists of icon-tile rows use
  `outlined` (white + hairline) so the pastel tiles sit on white.
- **Pastels** follow the preview: one per subject (dealbreakers carry `DealbreakerKind.tile`); the
  tile behind a destructive icon is blush.
- **Italic** is kept to one word per headline; the bio and the "You both said yes." line are upright.
- **Verdict ring** is a 40 pt ring with the seconds, beside the question; "Sealed." shows a blush tile with an envelope.
- **Tab bar keeps labels** (11 pt), as in the preview.

## Verification (after the last edit)

- tree-sitter-swift: 101 files, 0 with parse errors.
- `uib_verify.py`: 137 inits, 173 methods, 236 statics, 84 tokens, 105 store members, 191 cases — 0 problems.
- `verify.js`: 24 files against 395 types (331 inits, 149 typed calls, 272 named calls, 639 typed
  members, 527 statics, 199 cases) — 0 problems; 35 switches exhaustive.
- `builders.js`: 149 view-returning declarations — 0 problems.
- `check_project.py`: 0 problems (99 app files, 383 top-level type names).
- The three verifiers only read Features. I also ran `verify.js` with DesignSystem, Core and App as
  its targets (only its known SDK false positives remained) and a one-off script that checks every
  `Color.tempo.*`, `TempoGradient.*`, `TempoShadow.*`, `TempoRadius/Size/Spacing.*`, `TempoPastel.*`,
  `TempoTone.*`, `Animation.tempo.*`, `Font.tempo.*`, text style and card/button/ring kind reference
  in `Tempo/` and `TempoTests/` against the declarations: 0 unknown.
- Leftover grep over `ios/` (old hex values, `.dark`, glow, grain, mesh, particle, bloom, frosted,
  material, `Color.white`, vignette, removed token names): no hits. `Color.black` appears only in
  the scrim and the one shadow. Filled symbols remain only where intended (Yes heart, Leave,
  Accept, selected tab).

## Not sure about

- Nothing was compiled or seen on a device. The new pieces most likely to need a touch are listed
  in `ios/README.md`, row 15.
- SF Symbols used for the first time here: `moon`/`moon.fill`, `envelope`, `book`,
  `person.crop.circle.badge.xmark` (in menus), `exclamationmark.triangle`, `lock`, `checkmark.circle`.
  All are long-standing names; `figure.and.child.holdinghands` (already used) needs iOS 16+.
- Hiding the status bar over live video is my call; the alternative is a per-screen light status bar via UIKit.
- White chrome over very bright video relies on the hairline and the 8% shadow; worth a look on a real call.
- `Localizable.xcstrings` was not regenerated; new literals ("Tonight" as a title, the match line) will be
  picked up by Xcode's string extraction on first build.
