# Tempo design direction v2 — "Daylight" (REPLACES SPEC.md section 5 tokens, type and mood)

The founder asked for the feel of Hinge: simple white, confident editorial typography, nice icons, a few well-chosen colours. This is an original design in that spirit. Do NOT copy Hinge's logo, brand purple, illustrations, wordmark or exact screens; no reference to Hinge anywhere in code or copy.

Mood: a well-set magazine page in morning light. White space, black type, one warm accent, small moments of soft colour. Calm, grown-up, friendly. Light appearance ONLY (force `.preferredColorScheme(.light)`); no dark mode, no glows, no gradients on chrome, no frosted dark glass, no grain.

## Tokens (keep existing token NAMES where they exist so screens keep compiling; change values and add the new ones)
| Role | Value | Notes |
|---|---|---|
| Background (was ink) | `#FFFFFF` | every screen |
| Surface (was plum) | `#F7F5F2` | warm off-white for cards, fields, grouped rows |
| Surface 2 (was plumHi) | `#EFEBE6` | pressed states, their chat bubble |
| Hairline | `#E6E1DB` | 1 px dividers and card borders (borders, not shadows, define cards) |
| Text primary (was ivory) | `#1B1719` | near-black |
| Text secondary | `#6A6367` | |
| Text tertiary | `#A19A9E` | |
| Accent (was ember) | `#E4532F` flat warm vermilion | selection, links, the timer, my chat bubble, the active chess-clock half. Any "ember gradient" becomes this flat colour (if a gradient type must remain for API compatibility, make all stops this colour) |
| Accent soft | `#FCE9E3` | tinted backgrounds for accent chips |
| Primary button | fill `#1B1719`, text `#FFFFFF`, capsule, 54 pt tall | the main action is BLACK, not accent |
| Secondary button | white fill, 1 px `#1B1719` border, black text | |
| Yes (mint) | `#1F8A5B` with soft `#E0F0E7` | |
| No (ash) | `#6A6367` with soft `#EFEBE6` | |
| Warning (amber) | `#B86E00` with soft `#FBEFD6` | |
| Danger | `#C9372C` | |
| Premium (gold) | `#A8792A` ochre with soft `#FAF1DC` cream | paywall is white + cream card + ochre details + black CTA |
| Pastel icon tiles | blush `#FBE4DE`, sage `#E1EFE6`, butter `#FBF0D2`, sky `#E2ECF7`, lilac `#ECE6F5` | 36 pt rounded-10 tiles behind outlined icons in settings/profile/basics rows and paywall benefits; assign one pastel per category, consistently |
Radii: 12 chips, 16 cards, 28 sheets, capsule buttons. Shadows: none on cards; one soft shadow (y 8, blur 24, black 8%) only for floating things over video and sheets.

## Type
- Display: system serif (New York), **medium** weight (not bold), near-black, tracking −0.4 to −0.8, sizes 28–44 pt. Used for screen titles, names ("Maya, 29"), icebreaker questions, the big moments. Italic serif for one emphasised word at most.
- Body/UI: SF Pro, 17 body / 15 secondary / 13 caption. Eyebrows: 12 pt semibold, +0.8 tracking, uppercase, text-secondary.
- Numerals (timer, counts): SF Pro (default design, NOT rounded), monospaced digits, semibold.
- Generous line height and whitespace; left-aligned titles at 24 pt side margins; avoid centring everything.

## Icons
SF Symbols, outlined (non-filled) variants, regular weight, near-black, 22 pt in bars; the selected tab uses the filled variant in near-black with a small accent dot under it. Tab bar: plain white with a top hairline (no blur capsule). Icon + pastel tile pattern for rows as above.

## Signature elements, re-skinned
1. **The Pulse** (Tonight): on white. A 220 pt circle button: thin accent ring that gently breathes (scale 1 → 1.04), two faint concentric hairline rings drifting outward, centre label "Go online" in serif. Above it a left-aligned serif title "Tonight" and a line "23 compatible people online now" with a small green live dot. Searching: the ring becomes a rotating accent arc, label "Finding someone good…". Found: ring resolves into the partner's avatar circle, name in serif below.
2. **The Clock**: white capsule with hairline border and soft shadow at the top over the video: accent arc + "3:12" monospaced. Under 30 s the arc and digits turn warning-amber and pulse softly.
3. **The Turn Card**: a WHITE card (radius 16, soft shadow) over the lower video, styled like a prompt card: eyebrow "QUESTION 3", the question in 24 pt serif, then the two-sided chess-clock bar (track `#EFEBE6`, active half fills accent and drains), names under each half, and a black "Pass" capsule on your turn. Tucks to a small white chip.
4. **The Verdict**: video blurs light (white veil 70%); a white bottom sheet (radius 28): serif "Would you like to see Maya again?", two large circles — No (white, hairline border, outlined ✕ in text-secondary) and Yes (accent fill, white heart) — thin countdown ring; chosen state "Sealed." in serif with a small envelope icon.
5. **The Match**: white screen. Two photo circles overlapping with thin accent rings interlocked, "It's mutual." in 44 pt serif (the word "mutual" italic), one line of body copy, black "Say hello" button, text button "Keep dating". No particles; a single soft scale-in.
6. **No match / They left**: white, serif "Not this time.", "Next person in 3" with a thin draining accent arc, text button "Stop for tonight".
7. **Call chrome**: remote video full-bleed, a very light top and bottom black gradient (max 35%) only for legibility; self-view PiP with 2 px white border; control bar = white capsule with outlined black icons, Leave = accent-red filled circle with white icon.
8. **Chat**: white; my bubbles accent with white text; theirs Surface 2 with black text; composer is a Surface field with a black circular send button.
9. **Onboarding**: white, big left-aligned serif question per step, thin black progress line at top, selections as outlined capsule chips that fill black with white text when selected, black Continue button pinned at the bottom.
10. **Avatars without photos**: serif monogram in near-black on a deterministic pastel (from the five above).
Motion: quieter than v1 — short springs, fades and small slides; no bloom, no particles. Haptics unchanged. Accessibility rules from SPEC section 5 still apply (4.5:1 contrast: accent on white is for large text, icons and fills; small accent text must use `#C8431F`).
Copy voice unchanged.
