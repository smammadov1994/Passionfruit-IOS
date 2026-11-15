# DESIGN-API — Tempo design system ("Daylight")

Everything in `ios/Tempo/DesignSystem/`. Build screens only from what is listed here.
All types are `internal` (same app module); nothing depends on Core. Signatures below are copied from the code.
The look is defined by `/DESIGN-V2.md`: white page, near-black type, medium-weight serif headlines, outlined
SF Symbols, one flat vermilion accent, black primary buttons, pastel icon tiles, borders instead of shadows.

## 0. Rules that keep it compiling and consistent

1. Colors are always written in full: `Color.tempo.textPrimary`. There is **no** `.tempo.textPrimary` shorthand for `foregroundStyle`.
2. Text is styled with `.tempoText(.body)` (font + tracking + case + Dynamic Type), then `.foregroundStyle(Color.tempo.…)`. Do not use `.font(.system(...))` for text in screens (icons may).
3. Enum arguments can be written short (`variant: .secondary`, `ring: .ember`, `tint: .sage`).
4. Every countdown component takes the **server timestamp** (`endsAt`, `deadline`, `turnEndsAt`) plus the total duration from config. Never keep a local counter.
5. The app is **light only**. `RootView` applies `.preferredColorScheme(.light)`; `project.yml` sets `UIUserInterfaceStyle: Light`. Color sets have one value, no dark variant.
6. Color roles: **black** is the primary action and every selected state (chips, segments, switches, sliders). **Accent** (vermilion) is for the Pulse ring, the clock and turn bar, Yes, my chat bubble, unread dots, links. **Ochre + cream** are Premium only. **Mint** is the online dot and confirmations. Do not introduce other colors.
7. Small text is never accent `#E4532F`: use `Color.tempo.accentText` (`#C8431F`). Mint, amber and ochre do not reach 4.5:1 either: keep their small text near-black and carry the tone with an icon or a soft tint (`Chip` and `IconTile(tone:)` do this for you).
8. Icons are SF Symbols, **outlined** (no `.fill`), regular weight, near-black. Filled glyphs appear only where they sit white on a solid fill (the Yes heart, Leave, Accept) and in the selected tab.
9. Cards have a hairline border and no shadow. The one shadow (`TempoShadow.floating`) is only for chrome over video and for the bottom sheet.
10. Left-align: titles sit on the 24 pt margin. Do not centre whole screens.
11. The app name is never hardcoded here; components that show it take it as a `String` (see `PaywallHero`).
12. Strings passed in are shown verbatim (not localized by the component).

## 1. Tokens

### Colors — `Color.tempo.*` (`TempoColors`, asset-catalog backed)
The v1 names are kept so screens compile; prefer the role alias in new code.

| Token (alias) | Value | Use |
|---|---|---|
| `background` (`ink`) | #FFFFFF | every screen; also text/glyphs on black and accent fills (`onAccent`) |
| `surface` (`plum`) | #F7F5F2 | cards, fields, grouped content |
| `surface2` (`plumHi`) | #EFEBE6 | pressed states, tracks, their chat bubble |
| `hairline` | #E6E1DB | 1 pt dividers and card borders |
| `hairlineStrong` | near-black 24% | outline of unselected chips, focused composer |
| `textPrimary` (`ivory`) | #1B1719 | text; primary button fill |
| `textSecondary` | #6A6367 | secondary text |
| `textTertiary` | #A19A9E | placeholders, non-essential captions |
| `accent` (`ember`) | #E4532F | fills, icons, rings, large text |
| `accentText` | #C8431F | accent for small text |
| `accentSoft` | #FCE9E3 | tint behind accent chips |
| `yes` (`mint`) / `yesSoft` (`mintSoft`) | #1F8A5B / #E0F0E7 | Yes, online dot, confirmations |
| `no` (`ash`) / `noSoft` | #6A6367 / #EFEBE6 | No |
| `warning` (`amber`) / `warningSoft` (`amberSoft`) | #B86E00 / #FBEFD6 | warnings, last 30 s |
| `danger` / `dangerSoft` | #C9372C / danger 10% | destructive, errors, Leave |
| `premium` (`gold`) / `premiumSoft` (`goldSoft`) | #A8792A / #FAF1DC | Premium details / cream card |
| `pastelBlush` `pastelSage` `pastelButter` `pastelSky` `pastelLilac` | #FBE4DE #E1EFE6 #FBF0D2 #E2ECF7 #ECE6F5 | icon tiles, avatars without photos |

`enum TempoTone { case neutral, ember, mint, amber, danger, gold }` with `var color: Color` (icons, fills), `var textColor: Color` (small text, contrast-safe) and `var soft: Color` (tint). Used by `Chip`, `TempoRow`, `IconTile(tone:)`, `TempoToastItem`.
`enum TempoPastel { case blush, sage, butter, sky, lilac }` with `var color: Color` and `static func deterministic(for string: String) -> TempoPastel`.
Raw components for color math: `TempoRGB(hex: 0xE4532F)`, `.color`, `.color(opacity:)`, `.mixed(with:amount:)`; constants in `TempoPalette.*` (`ink plum plumHi hairline ivory ember mint ash amber danger gold`).

### Fills — `TempoGradient`
There are no gradients on chrome. These are flat (every stop the same color) and exist so a shape can take one `ShapeStyle` type whatever the tone.
```swift
static var ember: LinearGradient    // flat accent
static var amber: LinearGradient    // flat warning
static var gold: LinearGradient     // flat ochre
static var ash: LinearGradient      // flat ash
static func flat(_ color: Color) -> LinearGradient
static func scrim(fromTop: Bool, strength: Double = 0.35) -> LinearGradient   // black → clear, capped at 35%; video only
```
Prefer the plain color (`Color.tempo.accent`) in new code.

### Type — `.tempoText(_:)` and `Font.tempo.*`
```swift
func tempoText(_ style: TempoTextStyle) -> some View                 // on any View
func tempoText(_ style: TempoTextStyle, color: Color) -> some View
```
Usage: `Text("Not this time.").tempoText(.displayM).foregroundStyle(Color.tempo.textPrimary)`

| Style | Spec | Use |
|---|---|---|
| `.displayXL` / `.displayL` | 44 serif medium, −0.8 | the match moment, welcome headline |
| `.displayM` | 40 serif | "Not this time.", names on full-screen moments |
| `.displayS` | 34 serif | standard screen title, onboarding question |
| `.title` | 28 serif | sheet/card headlines, empty states, the Verdict question |
| `.titleS` | 24 serif | icebreaker question, names in lists |
| `.serifBody` | 20 serif | lines with a voice ("Finding someone good…") |
| `.body` | 17 | body |
| `.bodyEmphasis` | 17 semibold | row titles |
| `.button` | 17 semibold | button labels |
| `.secondary` | 15 | secondary text |
| `.secondaryEmphasis` | 15 medium | chips, compact buttons |
| `.caption` | 13 | captions |
| `.eyebrow` | 12 semibold, uppercase, +0.8 | eyebrows (prefer the `Eyebrow` view) |
| `.tabLabel` | 11 medium | tab bar labels |
| `.numeralXL` `.numeralL` `.numeral` `.numeralS` | 44 / 28 / 17 / 13 SF Pro semibold, monospaced digits | timers, counts, price |

Serif is always **medium** weight, never bold. Modifiers on a style: `.italic()`, `.weighted(_ newWeight: Font.Weight)`. Custom sizes: `TempoTextStyle.serif(_ size: CGFloat, tracking: CGFloat = -0.6, maxScale: CGFloat = 1.25)`, `TempoTextStyle.numerals(_ size: CGFloat, maxScale: CGFloat = 1.3)`.
Italic is for one emphasised word at most: `(Text("It's ") + Text("mutual.").italic()).tempoText(.displayL)`.
When an API needs a `Font`: `Font.tempo.displayL`, `.body`, `.numeral` … (same names as above), `Font.tempo.display(_ size: CGFloat)`, `Font.tempo.displayItalic(_ size: CGFloat)`, `Font.tempo.numerals(_ size: CGFloat)`.
All styles scale with Dynamic Type and are capped so large display type does not clip; add `.minimumScaleFactor(0.7)` + `.lineLimit(1)` on single-line display text.

### Spacing, radius, sizes
`TempoSpacing.xxs 4 · xs 8 · sm 12 · md 16 · lg 24 · xl 32 · xxl 48 · screen 24`
`TempoRadius.tile 10 · chip 12 · card 16 · sheet 28` (buttons and selectable chips are capsules)
`TempoSize.hitTarget 44 · buttonLarge 54 · buttonRegular 48 · buttonCompact 36 · iconTile 36 · barIcon 22 · pip (96×136) · hairline 1`
`func tempoScreenPadding() -> some View` — 24 pt horizontal padding for the content column.

### Motion — `Animation.tempo.*`
Quiet: short springs, fades, small slides. `standard` (response 0.38, damping 0.86 — the default) · `snappy` · `gentle` · `settle` (the single soft scale-in of key moments) · `press` · `fade`
```swift
func resolved(_ animation: Animation, reduceMotion: Bool) -> Animation
func standard(reduceMotion: Bool) -> Animation
```
Usage: `withAnimation(Animation.tempo.standard(reduceMotion: reduceMotion)) { phase = next }`
Transitions (all fall back to opacity under Reduce Motion):
```swift
static func tempoReplace(reduceMotion: Bool) -> AnyTransition   // fade + 8 pt slide, for phase changes
static func tempoRise(reduceMotion: Bool) -> AnyTransition      // from the bottom
static func tempoPop(reduceMotion: Bool) -> AnyTransition       // small scale + fade
```

### Surfaces and the one shadow
```swift
func tempoSurface<S: InsettableShape>(in shape: S, fill: Color = Color.tempo.ink, isFloating: Bool = false,
                                      showsBorder: Bool = true) -> some View
func tempoBottomSheet() -> some View                     // white, top corners 28, shadow, runs under the home indicator
func tempoShadow(_ shadow: TempoShadow) -> some View     // TempoShadow.floating (y 8, blur 24, black 8%) / .none
```
Usage: `content.padding(16).tempoSurface(in: RoundedRectangle(cornerRadius: TempoRadius.card, style: .continuous))` on the page;
add `isFloating: true` for anything that sits over video (white + hairline + the shadow).

### Helpers
`TempoCountdown.remaining(until:now:)`, `.fraction(until:now:total:)`, `.wholeSeconds(_:)`, `.clockString(_:)` ("3:12"), `.spokenString(_:)`.
`func tempoTracksActivity(_ isActive: Binding<Bool>) -> some View` — true while on screen; use to pause your own `TimelineView`.

## 2. Primitives

### Buttons
```swift
TempoButton(_ title: String, systemImage: String? = nil, variant: TempoButtonVariant = .primary,
            size: TempoButtonSize = .large, fullWidth: Bool = true, isLoading: Bool = false,
            action: @escaping () -> Void)
enum TempoButtonVariant { case primary, secondary, ghost, destructive, premium }
enum TempoButtonSize { case large /*54*/, regular /*48*/, compact /*36, 44 hit*/ }
TempoTextButton(_ title: String, color: Color = Color.tempo.textPrimary, action: @escaping () -> Void)
```
Usage: `TempoButton("Continue") { next() }` · `TempoButton("Check again", variant: .secondary, action: check)` · `TempoTextButton("Keep dating") { store.continueToNext() }`
For a custom label use the style: `Button { } label: { … }.buttonStyle(.tempoPrimary)` — also `.tempoSecondary`, `.tempoGhost`, `.tempoDestructive`, `.tempoPremium`, and `.tempo(_ variant: TempoButtonVariant, size: TempoButtonSize = .large, fullWidth: Bool = true)`.
`TempoButtonStyle(_ variant: TempoButtonVariant = .primary, size: TempoButtonSize = .large, fullWidth: Bool = true)`
`TempoPressStyle(scale: CGFloat = 0.94)` — bare press-scale for custom-shaped tappables.
A disabled button dims itself (35%); do not add your own `.opacity`.

Which variant:
- **primary** — BLACK capsule, white text. The single main action of a screen (Continue, Say hello, Save). One per screen.
- **secondary** — white, 1 pt black border, black text. The alternative beside a primary.
- **ghost** — text only, centred in a full-width row. Quiet exits under a primary (Not now, Restore purchases, Cancel).
- **destructive** — white, danger border and text. Delete account, unmatch, block, leave from the report sheet.
- **premium** — black like primary; an icon passed in is tinted cream. Only the purchase button and upsell entry points.
- **`TempoTextButton`** — underlined text on the margin, for quiet exits in left-aligned layouts (Stop for tonight, Keep dating).

```swift
IconCircleButton(systemImage: String, accessibilityLabel: String, isOn: Bool = true, offSystemImage: String? = nil,
                 kind: IconCircleButtonKind = .floating, size: CGFloat = 48, action: @escaping () -> Void)
enum IconCircleButtonKind { case floating, outlined, danger, plain }
```
`floating` = white disc + hairline + shadow (over video); `outlined` = the same without shadow (on the page); `danger` = red fill, white glyph; `plain` = no background.
Usage: `IconCircleButton(systemImage: "xmark", accessibilityLabel: "Close", kind: .plain) { dismiss() }` (off state fills near-black with a white glyph and shows `offSystemImage`).

### Slide to start
```swift
SlideToStart(title: String, systemImage: String = "arrow.right", action: @escaping () -> Void)
```
A 64 pt capsule of drifting watercolor (`BlotField.track`) with a white knob and a black icon. The washes start faint; the knob paints them in at full strength behind it, like a brush, and on arrival the whole track is painted. The icon never changes. Drag the knob to the end to fire `action` (springs back if released before 82%). It pushes back like a sprung trigger (see Haptics); a tick plus a small hop when it is only tapped. VoiceOver activates it as a button. Honors `.disabled`. For actions that should be deliberate: Tonight pins one to the bottom of the screen to go online (the camera turns on).

### Haptics — `TempoHaptics.shared`
Core Haptics patterns (haptics only, so a call's audio session is untouched; a no-op without haptic hardware).
```swift
func prepare()                                   // warm the engine when a screen with controls appears
func pressDown(); func pressUp(); func tick()    // button down / up, one selection step
func triggerBegin()                              // finger takes the slide knob
func triggerUpdate(progress: CGFloat, breakAt: CGFloat)   // resistance builds, teeth click, snaps slack at breakAt
func triggerEnd(completed: Bool)                 // landing thud, or the spring returning home
func startSearchPulse(); func stopSearchPulse()  // slow two-beat pulse while searching
func found()                                     // three rising beats: someone was found
func match()                                     // swell, two heavy beats, falling ticks: it's mutual
```
`TempoButtonStyle` and `TempoPressStyle` call `pressDown`/`pressUp` themselves (`tempoPressClick(isPressed:)`), with `Animation.tempo.press` (response 0.16, damping 0.62). `SlideToStart`, the date lobby and `MatchCelebration` drive the rest. Do not add another haptic on tap for controls that use those styles.

### Illustrations (asset catalog)
Watercolor PNGs with transparent backgrounds, rendered by `Tools/generate_art.py` in the same technique and palette as `marketing/`. Re-run the script to change them; never edit the PNGs.
| Asset | Size (pt) | Where |
|---|---|---|
| `ArtWelcome` | 354 × 330 | the open middle of Welcome |
| `ArtMutual` | 320 × 240 | behind the two portraits on the match screen |
| `ArtSpot` | 112 × 104 | behind the icon of `EmptyStateView` |
| `ArtGold` | 354 × 150 | top right of the paywall, behind the headline; the Premium card on Tonight |
| `BlotBlush` `BlotButter` `BlotSage` `BlotLilac` `BlotSky` `BlotAccent` | 220 × 220 | single washes, layered and moved by `BlotField` |
| `ArtCardSage` `ArtCardButter` `ArtCardBlush` `ArtCardLilac` `ArtCardSky` | 354 × 170 | trailing-corner wash of a Tonight card (`TonightArtCard`, in Features): keep text on the leading ~240 pt |
Usage: `Image("ArtTonight").resizable().scaledToFill()` as a `.background`, then clip. Decorative: hide from VoiceOver. One illustration per card or screen.

### Moving paint
```swift
BlotField(_ blots: [Blot], push: CGFloat = 0, isActive: Bool = true)
Blot(id: Int, hue: Blot.Hue, x: CGFloat, y: CGFloat, size: CGFloat, squash: CGFloat = 1, drift: CGFloat = 9, period: Double = 16, depth: CGFloat = 0)
BlotField.tonight   // the cluster on the Tonight card (236 pt tall, weighted right)
BlotField.track     // the wash along the slide control
```
Single washes multiply-blended on white, each wandering a few points, turning and breathing on its own period. `x` is in a 354 pt design width and scales; `y` and `size` are points. `push` 0...1 sweeps and swells blots by their `depth`. Still under Reduce Motion or when `isActive` is false. Use as a `.background`, then clip. Keep to one or two live fields per screen; elsewhere use the static `Art*` images.

### Launch
```swift
LaunchBloom(title: String, onFinished: @escaping () -> Void)
```
The opening moment, shown once per launch by `TempoApp` as an overlay: washes bloom from white until they fill the screen, the wordmark on top, then the paint thins out to reveal the app (about 2.4 s; a short fade under Reduce Motion). Launch argument `-skipBloom` turns it off.

`Blot.Motion`: `.wander` (default), `.bounce(dx:dy:)` (straight lines, reflecting off the field's edges; points per second), `.seep(dx:dy:)` (fades in, drifts, fades away, returns elsewhere every `period`).

The app icon (`AppIcon-1024.png`) is drawn by `Tools/generate_art.py` too: washes on paper, nothing else.

### Searching
```swift
SearchingPaint(gather: CGFloat = 0)     // 0 = searching, 1 = found; animatable
```
Full-bleed moving paint for the date lobby: two large washes circle each other and draw close, a vermilion spot brightens where they meet, pale washes wander behind and small drops seep in and out. Animate `gather` to 1 and the pair falls into one bloom at the centre (put the partner's photo there). Opaque; still under Reduce Motion. `PulseOrb` is no longer used by the lobby.

### Brand mark
```swift
BrandMark(size: CGFloat = 20)
```
The Passionfruit mark (`BrandFruit` asset): two washes mixing into purple with a leaf, the same drawing as the app icon. `PremiumBadge` uses it. Do not use `sparkles` or other stock symbols as a logo.

### Blot portraits and the splatter card
```swift
BlotPortrait(url: URL?, name: String, blot: String? = nil, size: CGFloat = 64, turn: Double = 0)
```
A person inside a watercolor blot, no circle: the photo is cut to the blot's torn shape, or the initial sits in the paint. Used for matches on Tonight, the found screen and the match screen. `VerdictPad`'s Yes and No are blots too. `TurnCard` stays a plain white floating card.

### Agent characters
```swift
AgentBuddy(persona: AgentPersona, size: CGFloat = 56, isThinking: Bool = false)
```
A match's agent as a little character: a watercolor blot body (ten colours, `Buddy*` assets, stretched and turned eight ways) with generated eyes, mouth, cheeks and something on its head. Bobs and blinks (faster bob while thinking); still under Reduce Motion. Leave about `size × 0.25` of headroom above it.

### Navigation
There is no tab bar. Tonight is home; the heart button in its header opens Matches (accent dot while unread); the cog in the Matches header opens You; Matches and You each start with a back `IconCircleButton` (`.outlined`, 44). All of it goes through `AppRouter.select(_:)`.

### Chips
```swift
Chip(_ text: String, systemImage: String? = nil, tone: TempoTone = .neutral)       // radius 12; neutral = outlined, toned = soft tint
SelectableChip(_ text: String, systemImage: String? = nil, isSelected: Bool, action: @escaping () -> Void)   // capsule; outlined → black fill, white text
FlowLayout(spacing: CGFloat = TempoSpacing.xs, lineSpacing: CGFloat = TempoSpacing.xs)   // wrapping Layout
```
Usage: `FlowLayout { ForEach(options, id: \.self) { o in SelectableChip(o, isSelected: picked.contains(o)) { toggle(o) } } }`

### Surfaces, labels and rows
```swift
Eyebrow(_ text: String, color: Color = Color.tempo.textSecondary)
ScreenHeader(eyebrow: String? = nil, title: String, emphasis: String? = nil, subtitle: String? = nil,
             alignment: HorizontalAlignment = .leading, style: TempoTextStyle = .displayS)
TempoCard(kind: TempoCardKind = .raised, padding: CGFloat = 20, @ViewBuilder content: () -> Content)
enum TempoCardKind { case raised, floating, outlined, gold }
FloatingCapsule(horizontalPadding: CGFloat = TempoSpacing.md, verticalPadding: CGFloat = 10, @ViewBuilder content: () -> Content)
IconTile(systemName: String, tint: TempoPastel)      // 36 pt, radius 10, pastel fill, outlined near-black icon
IconTile(systemName: String, tone: TempoTone)        // tone-colored icon on the tone's soft tint (danger: on blush)
SheetGrabber()
TempoDivider()
TempoRow(title: String, value: String? = nil, systemImage: String? = nil, tone: TempoTone = .neutral,
         tile: TempoPastel = .blush, showsChevron: Bool = true, action: @escaping () -> Void)
```
Cards: `raised` = surface + hairline (fields, notes, sliders); `outlined` = white + hairline (lists of icon-tile rows); `gold` = cream (Premium); `floating` = white + hairline + shadow (over video only).
Usage: `ScreenHeader(eyebrow: "About you", title: "What's your", emphasis: "first name?", subtitle: "First name only.")`
`TempoCard(kind: .outlined, padding: TempoSpacing.md) { VStack(spacing: 0) { TempoRow(title: "Community rules", systemImage: "checkmark.shield", tile: .sage) { } ; TempoDivider() ; … } }`
`FloatingCapsule { Text("Reconnecting…").tempoText(.caption) }` (over video)
Pastels: one per subject, kept wherever the subject appears. In use: sage = safety and rules · butter = notifications, "unlimited" · lilac = restore, terms · sky = privacy, sign out, filters · blush = people and the tile behind a danger icon. Dealbreakers carry their own (`DealbreakerKind.tile`, in Features).

### Inputs
```swift
TempoTextField(_ title: String, text: Binding<String>, prompt: String = "", systemImage: String? = nil,
               axis: Axis = .horizontal, errorMessage: String? = nil, characterLimit: Int? = nil)
TempoToggleRow(title: String, subtitle: String? = nil, systemImage: String? = nil, tile: TempoPastel = .sky, isOn: Binding<Bool>)
TempoSwitch(isOn: Bool)                                   // visual only; black when on
SegmentedPicker(selection: Binding<Value>, options: [SegmentedOption<Value>])     // Value: Hashable
SegmentedOption(value: Value, label: String)
SegmentedPicker(selection: Binding<String>, labels: [String])                     // label == value
RangeSliderRow(title: String, lower: Binding<Double>, upper: Binding<Double>, bounds: ClosedRange<Double>,
               step: Double = 1, minimumSpan: Double = 1, format: @escaping (Double) -> String = TempoSliderFormat.integer)
RangeSliderRow(title: String, lower: Binding<Int>, upper: Binding<Int>, bounds: ClosedRange<Int>, minimumSpan: Int = 1)
SliderRow(title: String, value: Binding<Double>, bounds: ClosedRange<Double>, step: Double = 1,
          format: @escaping (Double) -> String = TempoSliderFormat.integer)
SliderRow(title: String, value: Binding<Int>, bounds: ClosedRange<Int>,
          format: @escaping (Double) -> String = TempoSliderFormat.integer)
TempoSliderFormat.integer   // "29"      TempoSliderFormat.kilometers   // "25 km"
```
Fields sit on `surface` with a hairline that turns black on focus. Sliders: surface-2 track, black fill, white thumb with a black ring.
Usage: `TempoTextField("First name", text: $name, prompt: "What should we call you?").textContentType(.givenName)`
`TempoToggleRow(title: "Tell me when people are online", subtitle: "At most once every four hours.", systemImage: "bell", tile: .butter, isOn: $notify)`
`RangeSliderRow(title: "Age", lower: $ageMin, upper: $ageMax, bounds: 18...80)` · `SliderRow(title: "Maximum distance", value: $km, bounds: 1...160, format: TempoSliderFormat.kilometers)`
(With `Int` bindings the `Int` overloads are chosen automatically; write the bounds as integer literals.)

### Images
```swift
AvatarView(url: URL?, name: String, size: CGFloat = 56, ring: AvatarRing = .none, showsOnlineDot: Bool = false)
enum AvatarRing { case none, hairline, ember, gold }
TempoRemoteImage(url: URL?, name: String, monogramSize: CGFloat = 40)   // fills its frame; clip it yourself
```
Rings are thin (1.5–2 pt): `.ember` accent, `.gold` ochre.
Fallback (nil URL, loading, failure) is a near-black serif monogram on a deterministic per-name pastel. Loading uses `AsyncImage` → `URLCache.shared`.

### Feedback
```swift
LoadingDots(color: Color = Color.tempo.textPrimary, dotSize: CGFloat = 6)
ErrorBanner(message: String, retryTitle: String = "Try again", onRetry: (() -> Void)? = nil, onDismiss: (() -> Void)? = nil)
EmptyStateView(systemImage: String, title: String, message: String, actionTitle: String? = nil, action: (() -> Void)? = nil)
TempoToastItem(_ message: String, systemImage: String? = nil, tone: TempoTone = .neutral)
func tempoToast(item: Binding<TempoToastItem?>, duration: TimeInterval = 2.6) -> some View
TempoToast(item: TempoToastItem)        // the pill itself; rarely needed directly
```
`ErrorBanner` is white with a danger border; over video add `.tempoShadow(TempoShadow.floating)`. `EmptyStateView` is left-aligned with a blush icon circle. Toasts are white floating capsules.
`.tempoToast(item: $toast)` on the screen root, then `toast = TempoToastItem("Reported. Thank you.", systemImage: "checkmark.circle", tone: .mint)`.

### Background
```swift
InkBackground()                         // plain white, ignores safe areas (name kept from v1)
func inkBackground() -> some View
```
Usage: `ScrollView { … }.inkBackground()` or `ZStack { InkBackground(); content }`. There are no variants.

## 3. Signature components

```swift
PulseOrb(state: PulseOrbState, onlineCount: Int?, diameter: CGFloat = 220, idleTitle: String = "Go online",
         searchingTitle: String = "Finding someone good…", foundPhoto: URL? = nil, foundName: String? = nil,
         showsOnlineCount: Bool = true, action: @escaping () -> Void)
enum PulseOrbState { case idle, searching, found }
LiveCountLine(count: Int?)              // green dot + "23 compatible people online now"; LiveCountLine.text(for:)
```
On white: a thin accent ring breathing 1 → 1.04, two hairline rings drifting outward, the title in serif inside. Searching: the ring becomes a rotating accent arc around the searching line. Found: the partner's photo circle with a thin accent ring, name in serif below.
The circle is the button (tap in `.idle` → go online, tap in `.searching` → stop; inert in `.found`). Needs about `diameter × 1.4` square plus 60 pt.
The Pulse is used by the date lobby (searching, found). Tonight no longer shows it: the way in there is `SlideToStart`.

```swift
DateClockView(endsAt: Date, totalDuration: TimeInterval, warningThreshold: TimeInterval = 30)
```
A white floating capsule: small accent arc + "3:12". Amber and softly pulsing under the threshold. Centre it at the top of the call screen.

```swift
TurnCard(question: String, questionNumber: Int, myName: String, partnerName: String, isMyTurn: Bool,
         turnEndsAt: Date, turnDuration: TimeInterval, onPass: @escaping () -> Void, isCollapsed: Binding<Bool>)
```
A white prompt card (radius 16, floating): eyebrow "QUESTION 3", the question in 24 pt serif, the chess-clock bar with names under each half, a black "Pass" capsule on your turn. Drag down to tuck it into a white chip.

```swift
VerdictPad(partnerName: String, deadline: Date, totalWindow: TimeInterval,
           selection: Binding<VerdictChoice?>, onChoose: @escaping (VerdictChoice) -> Void)
enum VerdictChoice: String { case yes, no }
```
The CONTENT of the white bottom sheet: the question in serif with a thin countdown ring, No (white, hairline, outlined cross) and Yes (accent, white heart), and the "Sealed." state. It has its own 24 pt side padding.
Usage: `VStack(spacing: 0) { Spacer(); VerdictPad(…).padding(.top, 32).padding(.bottom, 16).tempoBottomSheet() }` over the video with `.blur(radius: 24)` and a 70% white veil (`CallVideoBackdrop(isDimmed: true)` does both).

```swift
MatchCelebration(myPhoto: URL?, myName: String, partnerPhoto: URL?, partnerName: String, headline: String = "It's mutual.",
                 onSayHello: @escaping () -> Void, onKeepDating: @escaping () -> Void)
```
Full white screen, left-aligned; brings its own background, do not wrap it. The last word of `headline` is set in italic. One scale-in, one haptic.

```swift
NextCountdown(endsAt: Date, total: TimeInterval, title: String, caption: String = "Next person in",
              stopTitle: String = "Stop for tonight", onFinished: (() -> Void)? = nil, onStop: @escaping () -> Void)
```
Left-aligned: serif title, "Next person in 3" beside a thin draining accent arc, an underlined text button. It has its own 24 pt side padding; put it on `InkBackground()`.

```swift
SelfViewPiP(initialCorner: PiPCorner = .topTrailing, size: CGSize = TempoSize.pip, margin: CGFloat = TempoSpacing.md,
            topInset: CGFloat = 0, bottomInset: CGFloat = 0, isCameraOff: Bool = false, @ViewBuilder content: () -> Content)
enum PiPCorner { case topLeading, topTrailing, bottomLeading, bottomTrailing }
CallControlBar(isMicMuted: Bool, isCameraOff: Bool, onToggleMic: @escaping () -> Void, onToggleCamera: @escaping () -> Void,
               onFlip: @escaping () -> Void, onReport: @escaping () -> Void, onLeave: @escaping () -> Void)
VideoScrim(topHeight: CGFloat = 160, bottomHeight: CGFloat = 260, strength: Double = 0.35)
ModerationWarningBanner(title: String = "Keep it respectful", message: String, onDismiss: (() -> Void)? = nil)
```
PiP: 2 pt white border. Control bar: white capsule, outlined black icons (a control that is off fills black), Leave = red circle with a white icon. Scrim: black, 35% at most. Warning: white floating card, amber icon tile, amber border.

```swift
PaywallHero(eyebrow: String, headline: String = "Never run out of", emphasis: String? = "evenings.")
BenefitRow(systemImage: String, title: String, detail: String, tint: TempoPastel = .butter)
PriceTag(price: String, period: String = "month", note: String? = nil)      // a cream card
PremiumBadge(text: String = "Premium", compact: Bool = false)               // cream capsule, ochre sparkle
LockedRow(title: String, detail: String? = nil, systemImage: String? = nil, tile: TempoPastel = .butter, action: @escaping () -> Void)
```
Paywall = white page, left-aligned `PaywallHero`, `BenefitRow`s, the cream `PriceTag`, `TempoButton("Start Premium", variant: .premium)`, restore as `.ghost`, close with `IconCircleButton(systemImage: "xmark", …, kind: .plain)` top-trailing.

```swift
OnboardingProgress(step: Int, total: Int)                       // one thin black line; step is 1-based
PhotoSlot(url: URL?, image: Image? = nil, isPrimary: Bool = false, isLoading: Bool = false,
          onTap: @escaping () -> Void, onRemove: (() -> Void)? = nil)      // 3:4, takes the width it is given
MessageBubble(text: String, isMine: Bool, timestamp: String? = nil, isPending: Bool = false, showsTail: Bool = true)
ChatComposer(text: Binding<String>, placeholder: String = "Message", isSending: Bool = false, onSend: @escaping () -> Void)
```
Bubbles: mine accent with white text, theirs surface 2 with near-black text. Composer: surface field, black circular send button, white bar with a top hairline; attach with `.safeAreaInset(edge: .bottom) { ChatComposer(…) }`.

`DesignGallery()` (`#if DEBUG`) shows everything with live toggles.

## 4. Composition guide

**Screen skeleton**
```swift
ScrollView {
    VStack(alignment: .leading, spacing: TempoSpacing.xl) {
        ScreenHeader(eyebrow: "You", title: "Your", emphasis: "profile.")
        TempoCard(kind: .outlined, padding: TempoSpacing.md) { … }
    }
    .tempoScreenPadding()
    .padding(.vertical, TempoSpacing.lg)
}
.inkBackground()
```
- Horizontal padding is always `tempoScreenPadding()` (24). Vertical rhythm: `xl` (32) between sections, `lg` (24) between blocks, `sm`/`md` inside cards. Be generous.
- Headline pattern: `Eyebrow` → serif headline (optionally one italic last word) → body in `textSecondary`, all left-aligned. Use `ScreenHeader`. One serif headline per screen; sentence case; short.
- Bottom call-to-action: `.safeAreaInset(edge: .bottom) { TempoButton(…).tempoScreenPadding().padding(.bottom, TempoSpacing.xs) }` on a white background. Black primary on top, ghost beneath.
- Lists of settings: `TempoCard(kind: .outlined, padding: TempoSpacing.md)` containing `TempoRow` / `TempoToggleRow` / `LockedRow` (each with an `IconTile`) separated by `TempoDivider()`. Section titles are `Eyebrow`s outside the card.
- Full-screen moments (no match, daily limit, call ended): left-aligned `VStack(alignment: .leading)` with `Spacer`s above and below the copy, actions at the bottom.
- Sheets: `.presentationCornerRadius(TempoRadius.sheet)`, `.presentationBackground { InkBackground() }`, `SheetGrabber()` at the top if the system indicator is hidden.
- Navigation bars: hide system backgrounds (`.toolbarBackground(.hidden, for: .navigationBar)`); tint is accent via `AccentColor`.
- No tab bar: see "Navigation" above.
- Loading: `LoadingDots()`; buttons use `isLoading:`. Errors: `ErrorBanner` inline at the top of the content with retry; transient confirmations: toast.

**Call screen layering (bottom → top)**
```swift
ZStack {
    RemoteVideoView().ignoresSafeArea()
    VideoScrim()
    SelfViewPiP(topInset: 56, bottomInset: 96, isCameraOff: off) { LocalVideoView() }
    VStack(spacing: TempoSpacing.sm) {
        DateClockView(endsAt: endsAt, totalDuration: total)
        if let warning { ModerationWarningBanner(message: warning) }
        Spacer()
        TurnCard(…)
        CallControlBar(…)
    }
    .tempoScreenPadding()
    .padding(.vertical, TempoSpacing.xs)
}
.statusBarHidden(true)   // the app is light, so status-bar text is dark: hide it over live video
```
Everything over video is white chrome with the hairline and the one shadow (`isFloating: true`, `FloatingCapsule`, `TempoCardKind.floating`, `IconCircleButtonKind.floating`). Never put bare text on video.

**Date flow backgrounds**: searching/connecting, no-match, they-left, limit, suspended = `InkBackground()`; verdict = blurred video + 70% white veil + `VerdictPad` in `.tempoBottomSheet()`; match = `MatchCelebration` alone.

**Motion**: change phases inside `withAnimation(Animation.tempo.standard(reduceMotion:))` and give each phase view `.transition(AnyTransition.tempoReplace(reduceMotion:))`. Components already handle their own haptics; do not add duplicates for the same event.

**Accessibility**: components carry their own labels. For your own icon-only buttons use `IconCircleButton` (label is required). Keep text out of fixed-height frames. Check any new small colored text against rule 7.
