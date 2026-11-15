#if DEBUG
import SwiftUI

/// Debug-only catalogue of every design-system token and component with live state toggles.
///
///     DesignGallery()
struct DesignGallery: View {
    init() {}

    var body: some View {
        NavigationStack {
            List {
                Section("Tokens") {
                    NavigationLink("Colors") { GalleryColorsPage() }
                    NavigationLink("Type") { GalleryTypePage() }
                }
                .listRowBackground(Color.tempo.surface)
                Section("Primitives") {
                    NavigationLink("Buttons") { GalleryButtonsPage() }
                    NavigationLink("Controls and inputs") { GalleryControlsPage() }
                    NavigationLink("Surfaces and feedback") { GallerySurfacesPage() }
                }
                .listRowBackground(Color.tempo.surface)
                Section("Signature") {
                    NavigationLink("Pulse orb") { GalleryPulsePage() }
                    NavigationLink("Date clock and next countdown") { GalleryClockPage() }
                    NavigationLink("Turn card") { GalleryTurnPage() }
                    NavigationLink("Verdict pad") { GalleryVerdictPage() }
                    NavigationLink("Match celebration") { GalleryMatchPage() }
                    NavigationLink("Call components") { GalleryCallPage() }
                    NavigationLink("Premium") { GalleryPremiumPage() }
                    NavigationLink("Profile and chat") { GalleryChatPage() }
                }
                .listRowBackground(Color.tempo.surface)
            }
            .scrollContentBackground(Visibility.hidden)
            .inkBackground()
            .navigationTitle("Design gallery")
        }
        .tint(Color.tempo.accent)
        .preferredColorScheme(ColorScheme.light)
    }
}

// MARK: - Page scaffold

private struct GalleryPage<Content: View>: View {
    let title: String
    let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TempoSpacing.lg) {
                content
            }
            .tempoScreenPadding()
            .padding(.vertical, TempoSpacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .inkBackground()
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(NavigationBarItem.TitleDisplayMode.inline)
    }
}

private struct GalleryLabel: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Eyebrow(text)
    }
}

// MARK: - Tokens

private struct GalleryColorsPage: View {
    var body: some View {
        GalleryPage("Colors") {
            GalleryLabel("Surfaces")
            swatch("background (ink) #FFFFFF", Color.tempo.background)
            swatch("surface (plum) #F7F5F2", Color.tempo.surface)
            swatch("surface2 (plumHi) #EFEBE6", Color.tempo.surface2)
            swatch("hairline #E6E1DB", Color.tempo.hairline)
            GalleryLabel("Text")
            swatch("textPrimary (ivory) #1B1719", Color.tempo.textPrimary)
            swatch("textSecondary #6A6367", Color.tempo.textSecondary)
            swatch("textTertiary #A19A9E", Color.tempo.textTertiary)
            GalleryLabel("Accent")
            swatch("accent (ember) #E4532F", Color.tempo.accent)
            swatch("accentText #C8431F", Color.tempo.accentText)
            swatch("accentSoft #FCE9E3", Color.tempo.accentSoft)
            semantic
            pastels
        }
    }

    @ViewBuilder
    private var semantic: some View {
        GalleryLabel("Semantic")
        pair("yes (mint) #1F8A5B", Color.tempo.yes, Color.tempo.yesSoft)
        pair("no (ash) #6A6367", Color.tempo.no, Color.tempo.noSoft)
        pair("warning (amber) #B86E00", Color.tempo.warning, Color.tempo.warningSoft)
        pair("premium (gold) #A8792A", Color.tempo.premium, Color.tempo.premiumSoft)
        swatch("danger #C9372C", Color.tempo.danger)
    }

    @ViewBuilder
    private var pastels: some View {
        GalleryLabel("Pastels")
        HStack(spacing: TempoSpacing.xs) {
            IconTile(systemName: "person", tint: TempoPastel.blush)
            IconTile(systemName: "checkmark.shield", tint: TempoPastel.sage)
            IconTile(systemName: "infinity", tint: TempoPastel.butter)
            IconTile(systemName: "bell", tint: TempoPastel.sky)
            IconTile(systemName: "doc.text", tint: TempoPastel.lilac)
        }
        Text("blush · sage · butter · sky · lilac")
            .tempoText(.caption)
            .foregroundStyle(Color.tempo.textSecondary)
    }

    private func chip(_ color: Color) -> some View {
        RoundedRectangle(cornerRadius: TempoRadius.chip, style: .continuous)
            .fill(color)
            .frame(width: 56, height: 40)
            .overlay {
                RoundedRectangle(cornerRadius: TempoRadius.chip, style: .continuous)
                    .strokeBorder(Color.tempo.hairline, lineWidth: 1)
            }
    }

    private func swatch(_ name: String, _ color: Color) -> some View {
        HStack(spacing: TempoSpacing.sm) {
            chip(color)
            Text(name)
                .tempoText(.secondary)
                .foregroundStyle(Color.tempo.textPrimary)
        }
    }

    /// A color beside its soft tint.
    private func pair(_ name: String, _ color: Color, _ soft: Color) -> some View {
        HStack(spacing: TempoSpacing.sm) {
            chip(color)
            chip(soft)
            Text(name)
                .tempoText(.secondary)
                .foregroundStyle(Color.tempo.textPrimary)
        }
    }
}

private struct GalleryTypePage: View {
    var body: some View {
        GalleryPage("Type") {
            sample("displayL 44", TempoTextStyle.displayL, "It's mutual.")
            sample("displayM 40", TempoTextStyle.displayM, "Not this time.")
            sample("displayS 34", TempoTextStyle.displayS, "Tonight")
            sample("title 28", TempoTextStyle.title, "Go online")
            sample("titleS 24", TempoTextStyle.titleS, "Which film could you watch every year?")
            sample("serifBody 20", TempoTextStyle.serifBody, "Finding someone good…")
            sample("body 17", TempoTextStyle.body, "Four minutes, face to face.")
            sample("secondary 15", TempoTextStyle.secondary, "Maya, 29 · 2 km away")
            sample("caption 13", TempoTextStyle.caption, "Resets at midnight")
            sample("eyebrow 12", TempoTextStyle.eyebrow, "Question 3")
            sample("numeralXL 44", TempoTextStyle.numeralXL, "$14.99")
            sample("numeral 17", TempoTextStyle.numeral, "3:12")
        }
    }

    private func sample(_ name: String, _ style: TempoTextStyle, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: TempoSpacing.xxs) {
            GalleryLabel(name)
            Text(text)
                .tempoText(style)
                .foregroundStyle(Color.tempo.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Primitives

private struct GalleryButtonsPage: View {
    @State private var isLoading: Bool = false
    @State private var isDisabled: Bool = false
    @State private var isMuted: Bool = false

    var body: some View {
        GalleryPage("Buttons") {
            TempoToggleRow(title: "Loading", isOn: $isLoading)
            TempoToggleRow(title: "Disabled", isOn: $isDisabled)
            TempoDivider()
            variants
                .disabled(isDisabled)
            GalleryLabel("Sizes")
            HStack(spacing: TempoSpacing.xs) {
                TempoButton("Regular", variant: TempoButtonVariant.secondary, size: TempoButtonSize.regular, fullWidth: false, action: {})
                TempoButton("Compact", variant: TempoButtonVariant.secondary, size: TempoButtonSize.compact, fullWidth: false, action: {})
            }
            GalleryLabel("Icon circle")
            HStack(spacing: TempoSpacing.sm) {
                IconCircleButton(systemImage: "mic", accessibilityLabel: "Microphone", isOn: !isMuted, offSystemImage: "mic.slash") {
                    isMuted.toggle()
                }
                IconCircleButton(systemImage: "xmark", accessibilityLabel: "Close", kind: IconCircleButtonKind.outlined, action: {})
                IconCircleButton(systemImage: "phone.down.fill", accessibilityLabel: "Leave", kind: IconCircleButtonKind.danger, action: {})
                IconCircleButton(systemImage: "gearshape", accessibilityLabel: "Settings", kind: IconCircleButtonKind.plain, action: {})
            }
        }
    }

    private var variants: some View {
        VStack(spacing: TempoSpacing.sm) {
            TempoButton("Go online", isLoading: isLoading, action: {})
            TempoButton("Keep dating", variant: TempoButtonVariant.secondary, isLoading: isLoading, action: {})
            TempoButton("Stop for tonight", variant: TempoButtonVariant.ghost, isLoading: isLoading, action: {})
            TempoButton("Delete account", variant: TempoButtonVariant.destructive, isLoading: isLoading, action: {})
            TempoButton("Continue", variant: TempoButtonVariant.premium, isLoading: isLoading, action: {})
            TempoTextButton("Keep dating", action: {})
        }
    }
}

private struct GalleryControlsPage: View {
    @State private var name: String = ""
    @State private var bio: String = "Ask me about the worst film I love."
    @State private var showsError: Bool = false
    @State private var notify: Bool = true
    @State private var gender: String = "Woman"
    @State private var ageMin: Int = 26
    @State private var ageMax: Int = 38
    @State private var distance: Int = 25
    @State private var picked: Set<String> = ["Long-term"]

    private let intentions: [String] = ["Long-term", "Short-term", "Marriage", "Figuring it out"]

    var body: some View {
        GalleryPage("Controls and inputs") {
            TempoToggleRow(title: "Show field error", isOn: $showsError)
            TempoTextField(
                "First name",
                text: $name,
                prompt: "What should we call you?",
                systemImage: "person",
                errorMessage: showsError ? "That doesn't look right." : nil
            )
            TempoTextField("About you", text: $bio, prompt: "A line or two", axis: Axis.vertical, characterLimit: 140)
            TempoToggleRow(title: "Tell me when singles are online", subtitle: "At most once every 4 hours.", systemImage: "bell", isOn: $notify)
            SegmentedPicker(selection: $gender, labels: ["Woman", "Man", "Nonbinary"])
            RangeSliderRow(title: "Age", lower: $ageMin, upper: $ageMax, bounds: 18...80)
            SliderRow(title: "Maximum distance", value: $distance, bounds: 1...160, format: TempoSliderFormat.kilometers)
            chips
        }
    }

    private var chips: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.sm) {
            GalleryLabel("Chips")
            FlowLayout {
                ForEach(intentions, id: \.self) { option in
                    SelectableChip(option, isSelected: picked.contains(option)) {
                        toggle(option)
                    }
                }
            }
            FlowLayout {
                Chip("2 km away", systemImage: "location")
                Chip("Long-term", tone: TempoTone.ember)
                Chip("Online", tone: TempoTone.mint)
                Chip("1 strike", tone: TempoTone.amber)
                Chip("Premium", tone: TempoTone.gold)
            }
        }
    }

    private func toggle(_ option: String) {
        if picked.contains(option) {
            picked.remove(option)
        } else {
            picked.insert(option)
        }
    }
}

private struct GallerySurfacesPage: View {
    @State private var toast: TempoToastItem? = nil
    @State private var showsOnline: Bool = true

    var body: some View {
        GalleryPage("Surfaces and feedback") {
            ScreenHeader(eyebrow: "Tonight", title: "Meet someone", emphasis: "new.", subtitle: "Four minutes, face to face.")
            TempoCard {
                VStack(alignment: .leading, spacing: TempoSpacing.xs) {
                    Eyebrow("Raised")
                    Text("Surface with a hairline. No shadow.").tempoText(.body, color: Color.tempo.textPrimary)
                }
            }
            TempoCard(kind: TempoCardKind.gold) {
                Text("Cream card, for Premium.").tempoText(.body, color: Color.tempo.textPrimary)
            }
            TempoCard(kind: TempoCardKind.outlined, padding: TempoSpacing.md) {
                VStack(spacing: 0) {
                    TempoRow(title: "Notifications", value: "On", systemImage: "bell", tile: TempoPastel.sky, action: {})
                    TempoDivider()
                    TempoRow(title: "Delete account", systemImage: "trash", tone: TempoTone.danger, showsChevron: false, action: {})
                }
            }
            avatars
            FloatingCapsule {
                Text("Maya, 29 · 2 km away").tempoText(.secondaryEmphasis)
            }
            LoadingDots()
            ErrorBanner(message: "Couldn't load your matches.", onRetry: {}, onDismiss: {})
            TempoButton("Show toast", variant: TempoButtonVariant.secondary, size: TempoButtonSize.regular) {
                toast = TempoToastItem("Reported. Thank you.", systemImage: "checkmark.circle", tone: TempoTone.mint)
            }
            EmptyStateView(
                systemImage: "bubble.left.and.bubble.right",
                title: "No matches yet",
                message: "When it's mutual, they'll be here.",
                actionTitle: "Go online",
                action: {}
            )
        }
        .tempoToast(item: $toast)
    }

    private var avatars: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.sm) {
            TempoToggleRow(title: "Online dot", isOn: $showsOnline)
            HStack(spacing: TempoSpacing.md) {
                AvatarView(url: nil, name: "Maya", size: 64, ring: AvatarRing.ember, showsOnlineDot: showsOnline)
                AvatarView(url: nil, name: "Jonas", size: 64, ring: AvatarRing.gold)
                AvatarView(url: nil, name: "Ines", size: 64, ring: AvatarRing.hairline)
                AvatarView(url: nil, name: "", size: 64)
            }
        }
    }
}

// MARK: - Signature

private struct GalleryPulsePage: View {
    @State private var stateIndex: String = "Idle"
    @State private var count: Int = 23

    private var orbState: PulseOrbState {
        switch stateIndex {
        case "Searching": return PulseOrbState.searching
        case "Found": return PulseOrbState.found
        default: return PulseOrbState.idle
        }
    }

    var body: some View {
        GalleryPage("Pulse orb") {
            SegmentedPicker(selection: $stateIndex, labels: ["Idle", "Searching", "Found"])
            PulseOrb(state: orbState, onlineCount: count, foundName: "Maya") {
                stateIndex = stateIndex == "Idle" ? "Searching" : "Idle"
            }
            .frame(maxWidth: .infinity)
            TempoButton("Add someone online", variant: TempoButtonVariant.secondary, size: TempoButtonSize.regular) {
                count += 1
            }
        }
    }
}

private struct GalleryClockPage: View {
    @State private var endsAt: Date = Date().addingTimeInterval(240)
    @State private var nextAt: Date = Date().addingTimeInterval(3)

    var body: some View {
        GalleryPage("Date clock and next countdown") {
            DateClockView(endsAt: endsAt, totalDuration: 240)
                .frame(maxWidth: .infinity)
                .padding(.vertical, TempoSpacing.lg)
                .background {
                    RoundedRectangle(cornerRadius: TempoRadius.card, style: .continuous).fill(Color.tempo.textSecondary)
                }
            HStack(spacing: TempoSpacing.xs) {
                jump("4:00", 240)
                jump("0:36", 36)
                jump("0:12", 12)
            }
            TempoDivider()
            NextCountdown(endsAt: nextAt, total: 3, title: "Not this time.", onStop: {})
            TempoButton("Restart countdown", variant: TempoButtonVariant.secondary, size: TempoButtonSize.regular) {
                nextAt = Date().addingTimeInterval(3)
            }
        }
    }

    private func jump(_ title: String, _ seconds: TimeInterval) -> some View {
        TempoButton(title, variant: TempoButtonVariant.secondary, size: TempoButtonSize.compact, fullWidth: false) {
            endsAt = Date().addingTimeInterval(seconds)
        }
    }
}

private struct GalleryTurnPage: View {
    @State private var isCollapsed: Bool = false
    @State private var isMyTurn: Bool = true
    @State private var index: Int = 0
    @State private var endsAt: Date = Date().addingTimeInterval(30)

    private let questions: [String] = [
        "What's a small thing that made this week better?",
        "Which film could you watch every year?",
        "What did you want to be at nine?"
    ]

    var body: some View {
        GalleryPage("Turn card") {
            TempoToggleRow(title: "My turn", isOn: $isMyTurn)
            TempoToggleRow(title: "Collapsed", isOn: $isCollapsed)
            TempoButton("Next question", variant: TempoButtonVariant.secondary, size: TempoButtonSize.regular) {
                index += 1
                endsAt = Date().addingTimeInterval(30)
            }
            GalleryLabel("Over video")
            TurnCard(
                question: questions[index % questions.count],
                questionNumber: index + 1,
                myName: "You",
                partnerName: "Maya",
                isMyTurn: isMyTurn,
                turnEndsAt: endsAt,
                turnDuration: 30,
                onPass: pass,
                isCollapsed: $isCollapsed
            )
        }
    }

    private func pass() {
        isMyTurn.toggle()
        endsAt = Date().addingTimeInterval(30)
    }
}

private struct GalleryVerdictPage: View {
    @State private var selection: VerdictChoice? = nil
    @State private var deadline: Date = Date().addingTimeInterval(20)

    var body: some View {
        VStack(spacing: 0) {
            TempoButton("Reset", variant: TempoButtonVariant.secondary, size: TempoButtonSize.regular, fullWidth: false) {
                selection = nil
                deadline = Date().addingTimeInterval(20)
            }
            .frame(maxHeight: .infinity)
            VerdictPad(partnerName: "Maya", deadline: deadline, totalWindow: 20, selection: $selection) { _ in }
                .padding(.top, TempoSpacing.xl)
                .padding(.bottom, TempoSpacing.lg)
                .tempoBottomSheet()
        }
        .background { Color.tempo.surface2.ignoresSafeArea() }
        .navigationTitle("Verdict pad")
        .navigationBarTitleDisplayMode(NavigationBarItem.TitleDisplayMode.inline)
    }
}

private struct GalleryMatchPage: View {
    @State private var replay: Int = 0

    var body: some View {
        MatchCelebration(
            myPhoto: nil,
            myName: "Seren",
            partnerPhoto: nil,
            partnerName: "Maya",
            onSayHello: { replay += 1 },
            onKeepDating: { replay += 1 }
        )
        .id(replay)
        .navigationBarTitleDisplayMode(NavigationBarItem.TitleDisplayMode.inline)
    }
}

private struct GalleryCallPage: View {
    @State private var isMicMuted: Bool = false
    @State private var isCameraOff: Bool = false
    @State private var showsWarning: Bool = true

    var body: some View {
        ZStack {
            Color.tempo.textSecondary
                .ignoresSafeArea()
            VideoScrim()
            SelfViewPiP(topInset: 56, bottomInset: 96, isCameraOff: isCameraOff) {
                Color.tempo.pastelSky
            }
            VStack(spacing: TempoSpacing.md) {
                DateClockView(endsAt: Date().addingTimeInterval(200), totalDuration: 240)
                if showsWarning {
                    ModerationWarningBanner(message: "Sexual language isn't allowed here. One more and the date ends.") {
                        showsWarning = false
                    }
                }
                Spacer()
                CallControlBar(
                    isMicMuted: isMicMuted,
                    isCameraOff: isCameraOff,
                    onToggleMic: { isMicMuted.toggle() },
                    onToggleCamera: { isCameraOff.toggle() },
                    onFlip: {},
                    onReport: { showsWarning = true },
                    onLeave: {}
                )
            }
            .tempoScreenPadding()
            .padding(.vertical, TempoSpacing.xs)
            .animation(Animation.tempo.standard, value: showsWarning)
        }
        .navigationBarTitleDisplayMode(NavigationBarItem.TitleDisplayMode.inline)
    }
}

private struct GalleryPremiumPage: View {
    var body: some View {
        GalleryPage("Premium") {
            PaywallHero(eyebrow: "Premium")
            BenefitRow(systemImage: "infinity", title: "Unlimited dates", detail: "Keep going as long as the night does.")
            BenefitRow(systemImage: "slider.horizontal.3", title: "Dealbreaker filters", detail: "Intentions, children, faith, and more.")
            BenefitRow(systemImage: "bolt", title: "Front of the line", detail: "Get paired first when it's busy.")
            PriceTag(price: "$14.99", period: "month", note: "Cancel anytime in Settings.")
            TempoButton("Continue", variant: TempoButtonVariant.premium, action: {})
            TempoButton("Restore purchases", variant: TempoButtonVariant.ghost, size: TempoButtonSize.regular, action: {})
            TempoCard(kind: TempoCardKind.outlined, padding: TempoSpacing.md) {
                VStack(spacing: 0) {
                    LockedRow(title: "Religion", detail: "Any", systemImage: "book", action: {})
                    TempoDivider()
                    LockedRow(title: "Children", detail: "Any", systemImage: "figure.and.child.holdinghands", action: {})
                }
            }
            HStack(spacing: TempoSpacing.sm) {
                PremiumBadge()
                PremiumBadge(compact: true)
            }
        }
    }
}

private struct GalleryChatPage: View {
    @State private var draft: String = ""
    @State private var step: Int = 2
    @State private var sent: [String] = []

    var body: some View {
        VStack(spacing: 0) {
            GalleryPage("Profile and chat") {
                OnboardingProgress(step: step, total: 6)
                TempoButton("Next step", variant: TempoButtonVariant.secondary, size: TempoButtonSize.compact, fullWidth: false) {
                    step = step >= 6 ? 1 : step + 1
                }
                HStack(spacing: TempoSpacing.sm) {
                    PhotoSlot(url: nil, image: Image(systemName: "person.crop.rectangle"), isPrimary: true, onTap: {}, onRemove: {})
                    PhotoSlot(url: nil, onTap: {})
                    PhotoSlot(url: nil, isLoading: true, onTap: {})
                }
                messages
            }
            ChatComposer(text: $draft) {
                sent.append(draft)
                draft = ""
            }
        }
    }

    private var messages: some View {
        VStack(spacing: TempoSpacing.xs) {
            MessageBubble(text: "That was the fastest four minutes of my week.", isMine: false, timestamp: "21:04")
            MessageBubble(text: "Same. You still owe me the end of the ferry story.", isMine: true, timestamp: "21:05")
            ForEach(sent, id: \.self) { text in
                MessageBubble(text: text, isMine: true)
            }
        }
    }
}

#Preview("Design gallery") {
    DesignGallery()
}
#endif
