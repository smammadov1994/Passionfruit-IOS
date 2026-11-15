# NOTES — UI agent B (date flow and calls)

Scope: `ios/Tempo/Features/DateFlow/` and `ios/Tempo/Features/Call/`. Core and DesignSystem were not modified.

## What is here

| File | Contents |
|---|---|
| `Call/CallChrome.swift` | Shared call chrome: `CallVideoBackdrop`, `CallSelfView`, `CallPartnerLabel`, `CallStatusPill`, `CallConnectionHint`, `CallPermissionView`, `keepsScreenAwake(_:)`, `CallAnnouncer` |
| `Call/MatchCallView.swift` | `MatchCallView(match:)`: outgoing, incoming, connecting, live, ended, permission issue |
| `Call/ReportSheet.swift` | `ReportSheet(partnerName:onSubmit:onBlock:)` plus a second init with `onLeave:` |
| `DateFlow/DateFlowView.swift` | `DateFlowView()`: the persistent container, sheets, announcements, background handling; `DatePermissionNotice` |
| `DateFlow/DateFlowStage.swift` | `DatePhase` → screen mapping (exhaustive), announcement copy |
| `DateFlow/DateLobbyView.swift` | searching + connecting (one orb that blooms) |
| `DateFlow/DateLiveView.swift` | live overlay: partner, clock, hints, warning, Turn Card, controls, final-seconds ticks |
| `DateFlow/DateVerdictView.swift` | deciding + awaitingResult (the pad seals in place) |
| `DateFlow/DateOutcomeViews.swift` | matched, noMatch, partnerLeft, ended(reason) |
| `DateFlow/DateNoticeViews.swift` | limitReached, suspended, `CommunityRulesSheet` |
| `DateFlow/DateFlowPreviews.swift` | one `#Preview` per phase |

## Verification

No Swift compiler here. All 11 files parse with tree-sitter-swift (`node ~/.tempo-tools/check.js <dirs>`).
`python3 ~/.tempo-tools/uib_verify.py` cross-checks them against the Core, App and DesignSystem sources:
initializer labels (139 calls), method labels (177), static members (234), design tokens (91), store
members (110) and enum cases with payload labels (201). 0 problems. The script was tested against a file
of deliberate mistakes and caught all 13. It does not check types, optionality or actor isolation.

## Gaps in Core / DesignSystem, and what I did instead

1. **Permission issue is raised while the phase is `.idle`**, so the `fullScreenCover` (open only while
   `phase != .idle`) is closed when it appears. `DateFlowView` still renders it (in case the cover's condition
   is ever widened), and `DatePermissionNotice()` is public for use outside the cover. Agent A already shows
   its own card on Tonight, which is what users see today.
2. **The remote video is torn down at `date.ended`** (`finishCallMedia()` calls `video.endCall()` before the
   phase becomes `.deciding`). The video surface stays mounted through deciding and awaitingResult and is
   blurred and dimmed as designed, but what it shows then depends on the service: the demo keeps its
   animated placeholder; the live renderer most likely holds the last frame or goes black. If it goes black
   the Verdict backdrop is plain ink. Keeping the last frame would need a change in `LiveVideoCallService`.
3. **`NextCountdown` has no subtitle.** The second line of the preview ("No hard feelings. The night's still
   young.") is shown as an eyebrow above the title instead ("No hard feelings" / "Not this time.").
4. **`ReportSheet`'s contract has no result channel**: `onSubmit` is synchronous, so the sheet confirms
   optimistically. If `dateStore.report` fails, the failure shows as the flow's error banner
   (`dateStore.lastError`) once the sheet is closed.
5. **"Leave this date" after reporting** is not in the agreed `ReportSheet` signature. Added as a second
   initializer (`…onBlock:onLeave:`); the agreed three-argument initializer is unchanged and unambiguous.
6. **Report target safety**: `DateStore.report` and `blockPartner` act on "the current or just-finished
   partner". A sheet left open across the 3 s interstitial could otherwise point at the next person, so the
   flow closes the sheet when a different partner is paired and refuses to send for a stale target.
7. **Final-seconds haptics**: `DateClockView` already ticks once at 10 s. The flow adds a light tick for
   seconds 9 to 1 only, so nothing fires twice.
8. **No debug hook for `permissionIssue`**: the permission preview shows `CallPermissionView` directly.
9. **"Say hello" routing**: `dateStore.goOffline()`, then `environment.pendingRoute = .chat(matchId:)`
   (agent A's `TabShell` consumes it). A match the server has not delivered in full (`id` starting
   `pending-`, not in `MatchesStore`) routes to `.matches` instead.
10. **Background**: Core does nothing on backgrounding beyond keeping audio and reconnecting the socket on
    return. The flow follows that: if the date ended while away, the store is already in that phase and the
    matching screen shows; if it is still running, a short "You're back" toast and announcement.
11. **Portrait lock** is `UISupportedInterfaceOrientations` in `project.yml` (Core). Nothing is done in the views.

## Dependencies on agent A

- `PaywallView()` — presented as a sheet from the limit screen. It did not exist yet when this was written.
- `CommunityRulesContent()` (Features/Shared) — embedded in `CommunityRulesSheet` so the rules read the same everywhere.

## Decisions

- Tapping the orb while searching stops the search (DesignSystem behaviour), as well as the Cancel button.
- The Verdict shows a "Make this my last one tonight" option (`stopAfterThis()` during a date).
- The moderation-ended screen offers "Report <name>", because both people see that screen.
- Timed-out decisions show the sealed state with "Time ran out, so this one counts as a no."
- The screen is kept awake while searching as well as during a date; the previous idle-timer value is restored.
- Strings are plain literals, not `String(localized:)`. DesignSystem components show strings verbatim.

## Least sure it compiles

1. Two `ReportSheet` initializers that differ only by a trailing `onLeave:`; a call written with a trailing
   closure for `onBlock` should still resolve to the three-argument one, but that is the first thing to check.
2. `.tempoText(.serifBody.weighted(Font.Weight.semibold))` (implicit-member chain) in `CallPartnerLabel`.
3. `@Bindable var store = dateStore` followed by `return ZStack { … }` in `DateTurnCardHost.body`.
4. `KeepScreenAwakeModifier` and `CallAnnouncer` assume the iOS 18 SDK, where `View` and `ViewModifier`
   are `@MainActor`.
5. `.blur` on the UIKit-backed `RemoteVideoView` compiles; whether a Metal video layer actually blurs on
   device needs a real-device check.
