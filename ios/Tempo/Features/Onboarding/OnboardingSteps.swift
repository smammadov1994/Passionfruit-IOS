import SwiftUI

// Each step is a small view that edits `session.draft`. The container (`OnboardingFlow`) owns
// the progress bar, the Continue button and validation.

// MARK: - First name

struct OnboardingNameStep: View {
    private let onSubmit: () -> Void

    @Environment(SessionStore.self) private var session

    init(onSubmit: @escaping () -> Void) {
        self.onSubmit = onSubmit
    }

    private var errorMessage: String? {
        let draft: OnboardingDraft = session.draft
        if draft.trimmedFirstName.isEmpty || draft.isNameValid {
            return nil
        }
        return String(localized: "Use between 2 and 30 characters.")
    }

    var body: some View {
        @Bindable var session = session
        return VStack(alignment: .leading, spacing: TempoSpacing.lg) {
            ScreenHeader(
                eyebrow: String(localized: "Welcome"),
                title: String(localized: "What's your"),
                emphasis: String(localized: "first name?"),
                subtitle: String(localized: "It's what the person across from you will see. First name only.")
            )
            TempoTextField(
                String(localized: "First name"),
                text: $session.draft.firstName,
                prompt: String(localized: "What should we call you?"),
                errorMessage: errorMessage,
                characterLimit: 30
            )
            .textContentType(.givenName)
            .textInputAutocapitalization(.words)
            .autocorrectionDisabled(true)
            .submitLabel(.continue)
            .onSubmit {
                onSubmit()
            }
        }
    }
}

// MARK: - Birthdate

struct OnboardingBirthdateStep: View {
    @Binding private var date: Date
    @Binding private var hasPicked: Bool

    init(date: Binding<Date>, hasPicked: Binding<Bool>) {
        self._date = date
        self._hasPicked = hasPicked
    }

    private var range: ClosedRange<Date> {
        let now: Date = Date()
        let earliest: Date = Calendar.current.date(byAdding: .year, value: -120, to: now) ?? now
        return earliest...now
    }

    private var ageLine: String {
        guard hasPicked else {
            return String(localized: "Scroll to your date of birth.")
        }
        let age: Int = max(0, Birthdate.age(from: date, calendar: Calendar.current))
        return String(localized: "That makes you \(age).")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.lg) {
            ScreenHeader(
                eyebrow: String(localized: "About you"),
                title: String(localized: "When were you"),
                emphasis: String(localized: "born?"),
                subtitle: String(localized: "\(Brand.name) is for adults \(Birthdate.minimumAge) and over. People see your age, never your birthday.")
            )
            TempoCard(kind: TempoCardKind.raised, padding: TempoSpacing.xs) {
                DatePicker(
                    String(localized: "Date of birth"),
                    selection: $date,
                    in: range,
                    displayedComponents: .date
                )
                .datePickerStyle(.wheel)
                .labelsHidden()
                .frame(maxWidth: .infinity)
            }
            Text(ageLine)
                .tempoText(.body)
                .foregroundStyle(hasPicked ? Color.tempo.textPrimary : Color.tempo.textSecondary)
                .contentTransition(.numericText())
                .accessibilityAddTraits(AccessibilityTraits.updatesFrequently)
        }
        .onChange(of: date) { _, _ in
            hasPicked = true
        }
    }
}

/// The kind dead end for anyone under 18. There is no way forward from here.
struct UnderageView: View {
    private let canStartOver: Bool
    private let onStartOver: () -> Void
    private let onSignOut: () -> Void

    init(canStartOver: Bool, onStartOver: @escaping () -> Void, onSignOut: @escaping () -> Void) {
        self.canStartOver = canStartOver
        self.onStartOver = onStartOver
        self.onSignOut = onSignOut
    }

    var body: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.lg) {
            Spacer(minLength: 0)
            ScreenHeader(
                eyebrow: String(localized: "Not yet"),
                title: String(localized: "See you when you're"),
                emphasis: String(localized: "\(Birthdate.minimumAge)."),
                subtitle: String(localized: "\(Brand.name) is live video between adults, so we can't let you in yet. Thanks for being honest about your age. That matters more than you'd think.")
            )
            Spacer(minLength: 0)
        }
        .tempoScreenPadding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: TempoSpacing.xs) {
                TempoButton(String(localized: "Sign out"), variant: TempoButtonVariant.secondary, action: onSignOut)
                if canStartOver {
                    TempoButton(
                        String(localized: "Start over (demo only)"),
                        variant: TempoButtonVariant.ghost,
                        size: TempoButtonSize.regular,
                        action: onStartOver
                    )
                }
            }
            .tempoScreenPadding()
            .padding(.bottom, TempoSpacing.xs)
        }
        .inkBackground()
    }
}

// MARK: - Gender and interest

struct OnboardingIdentityStep: View {
    @Environment(SessionStore.self) private var session

    init() {}

    var body: some View {
        @Bindable var session = session
        return VStack(alignment: .leading, spacing: TempoSpacing.lg) {
            ScreenHeader(
                eyebrow: String(localized: "About you"),
                title: String(localized: "Who are you, and who would you like to"),
                emphasis: String(localized: "meet?"),
                style: TempoTextStyle.title
            )
            IdentityFields(gender: $session.draft.gender, interestedIn: $session.draft.interestedIn)
        }
    }
}

// MARK: - Photos

struct OnboardingPhotosStep: View {
    init() {}

    var body: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.lg) {
            ScreenHeader(
                eyebrow: String(localized: "Photos"),
                title: String(localized: "Show them who's"),
                emphasis: String(localized: "calling."),
                subtitle: String(localized: "Your first photo appears when you're paired, just before the video starts.")
            )
            PhotoGridEditor()
        }
    }
}

// MARK: - Bio

struct OnboardingBioStep: View {
    @Environment(SessionStore.self) private var session

    init() {}

    var body: some View {
        @Bindable var session = session
        return VStack(alignment: .leading, spacing: TempoSpacing.lg) {
            ScreenHeader(
                eyebrow: String(localized: "About you"),
                title: String(localized: "A line or two about"),
                emphasis: String(localized: "you."),
                subtitle: String(localized: "Short is good. You'll do the talking in person.")
            )
            BioField(text: $session.draft.bio)
        }
    }
}

// MARK: - Location

struct OnboardingLocationStep: View {
    @Environment(SessionStore.self) private var session
    @State private var failure: String?
    @State private var tasks: TaskBag = TaskBag()

    init() {}

    private var hasCoordinates: Bool {
        session.draft.lat != nil && session.draft.lng != nil
    }

    var body: some View {
        @Bindable var session = session
        return VStack(alignment: .leading, spacing: TempoSpacing.lg) {
            ScreenHeader(
                eyebrow: String(localized: "Location"),
                title: String(localized: "Meet people who are actually"),
                emphasis: String(localized: "nearby."),
                subtitle: String(localized: "We use your location once to find your city and to keep dates within your distance. People see how far away you are, never where you are.")
            )
            if let failure {
                ErrorBanner(message: failure, onDismiss: { self.failure = nil })
            }
            TempoButton(
                hasCoordinates ? String(localized: "Update my location") : String(localized: "Use my location"),
                systemImage: "location",
                variant: TempoButtonVariant.secondary,
                isLoading: session.isLocating,
                action: { detect() }
            )
            if hasCoordinates {
                Chip(String(localized: "Location found"), systemImage: "checkmark", tone: TempoTone.mint)
            }
            TempoTextField(
                String(localized: "City"),
                text: $session.draft.city,
                prompt: String(localized: "Or type your city"),
                systemImage: "mappin.and.ellipse",
                characterLimit: 60
            )
            .textContentType(.addressCity)
            .textInputAutocapitalization(.words)
            .submitLabel(.done)
        }
        .onDisappear {
            tasks.cancelAll()
        }
    }

    private func detect() {
        failure = nil
        tasks.run("locate") {
            let found: Bool = await session.detectLocation()
            if found || Task.isCancelled {
                return
            }
            failure = session.lastError?.userMessage ?? String(localized: "We couldn't find your location. Type your city instead.")
            session.lastError = nil
        }
    }
}

// MARK: - Basics

struct OnboardingBasicsStep: View {
    @Environment(SessionStore.self) private var session

    init() {}

    var body: some View {
        @Bindable var session = session
        return VStack(alignment: .leading, spacing: TempoSpacing.lg) {
            ScreenHeader(
                eyebrow: String(localized: "The basics"),
                title: String(localized: "A few things that"),
                emphasis: String(localized: "matter."),
                subtitle: String(localized: "All optional. They let people who care about the same things find you, and you can change them later.")
            )
            BasicsFields(
                intention: $session.draft.intention,
                children: $session.draft.children,
                religion: $session.draft.religion,
                education: $session.draft.education,
                smoking: $session.draft.smoking,
                drinking: $session.draft.drinking
            )
        }
    }
}

// MARK: - Camera and microphone

struct OnboardingMediaStep: View {
    private let issue: PermissionIssue?
    private let hasAsked: Bool
    private let onDismissIssue: () -> Void

    @Environment(ConfigStore.self) private var configStore

    init(issue: PermissionIssue?, hasAsked: Bool, onDismissIssue: @escaping () -> Void) {
        self.issue = issue
        self.hasAsked = hasAsked
        self.onDismissIssue = onDismissIssue
    }

    var body: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.lg) {
            ScreenHeader(
                eyebrow: String(localized: "Camera and microphone"),
                title: String(localized: "Dates happen"),
                emphasis: String(localized: "live."),
                subtitle: String(localized: "Every date is a \(TempoFormat.durationAdjective(configStore.dateDuration)) video call, so \(Brand.name) needs your camera and microphone.")
            )
            TempoCard(kind: TempoCardKind.outlined, padding: TempoSpacing.md) {
                VStack(alignment: .leading, spacing: 0) {
                    OnboardingPoint(
                        systemImage: "video",
                        title: String(localized: "Only while you're online"),
                        detail: String(localized: "Your camera and microphone are used when you go online and during a date. Never in the background."),
                        tint: TempoPastel.sage
                    )
                    TempoDivider()
                    OnboardingPoint(
                        systemImage: "checkmark.shield",
                        title: String(localized: "Checked for everyone's safety"),
                        detail: String(localized: "During a date, frames from your camera are checked automatically for nudity, and what you say is checked on your phone for sexual language."),
                        tint: TempoPastel.sage
                    )
                    TempoDivider()
                    OnboardingPoint(
                        systemImage: "mic.slash",
                        title: String(localized: "You stay in control"),
                        detail: String(localized: "Mute, turn your camera off, or leave at any moment."),
                        tint: TempoPastel.sage
                    )
                }
            }
            status
        }
    }

    @ViewBuilder
    private var status: some View {
        if let issue {
            PermissionIssueCard(
                issue: issue,
                onOpenSettings: { SystemSettings.open() },
                onDismiss: onDismissIssue
            )
        } else if hasAsked {
            Chip(String(localized: "Camera and microphone are ready"), systemImage: "checkmark", tone: TempoTone.mint)
        }
    }
}

/// A pastel icon tile, a title and a sentence. Used by the priming screens.
struct OnboardingPoint: View {
    private let systemImage: String
    private let title: String
    private let detail: String
    private let tint: TempoPastel

    init(systemImage: String, title: String, detail: String, tint: TempoPastel = TempoPastel.sky) {
        self.systemImage = systemImage
        self.title = title
        self.detail = detail
        self.tint = tint
    }

    var body: some View {
        HStack(alignment: .top, spacing: TempoSpacing.md) {
            IconTile(systemName: systemImage, tint: tint)
            VStack(alignment: .leading, spacing: TempoSpacing.xxs) {
                Text(title)
                    .tempoText(.bodyEmphasis)
                    .foregroundStyle(Color.tempo.textPrimary)
                Text(detail)
                    .tempoText(.secondary)
                    .foregroundStyle(Color.tempo.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, TempoSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Community rules

struct OnboardingRulesStep: View {
    @Binding private var hasAccepted: Bool

    init(hasAccepted: Binding<Bool>) {
        self._hasAccepted = hasAccepted
    }

    var body: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.lg) {
            ScreenHeader(
                eyebrow: String(localized: "Community rules"),
                title: String(localized: "Keep it"),
                emphasis: String(localized: "respectful."),
                subtitle: String(localized: "These keep every date safe. Read them once; they're always in You.")
            )
            TempoCard(kind: TempoCardKind.outlined, padding: TempoSpacing.md) {
                CommunityRulesContent()
            }
            TempoCard(kind: TempoCardKind.raised, padding: TempoSpacing.md) {
                TempoToggleRow(
                    title: String(localized: "I've read the rules and I'll follow them"),
                    isOn: $hasAccepted
                )
            }
        }
    }
}

// MARK: - Notifications

struct OnboardingNotificationsStep: View {
    init() {}

    var body: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.lg) {
            ScreenHeader(
                eyebrow: String(localized: "Notifications"),
                title: String(localized: "Know when compatible people are"),
                emphasis: String(localized: "online."),
                subtitle: String(localized: "\(Brand.name) only works when people are here at the same time. We'll tell you when it's a good moment.")
            )
            TempoCard(kind: TempoCardKind.outlined, padding: TempoSpacing.md) {
                VStack(alignment: .leading, spacing: 0) {
                    OnboardingPoint(
                        systemImage: "bell",
                        title: String(localized: "Only when it's worth it"),
                        detail: String(localized: "One notification when several compatible people are online now.")
                    )
                    TempoDivider()
                    OnboardingPoint(
                        systemImage: "clock",
                        title: String(localized: "Never noisy"),
                        detail: String(localized: "At most once every four hours.")
                    )
                    TempoDivider()
                    OnboardingPoint(
                        systemImage: "slider.horizontal.3",
                        title: String(localized: "Yours to change"),
                        detail: String(localized: "Turn it off anytime in You.")
                    )
                }
            }
        }
    }
}

#Preview("Onboarding steps") {
    ScrollView {
        VStack(alignment: .leading, spacing: TempoSpacing.xxl) {
            OnboardingNameStep(onSubmit: {})
            OnboardingIdentityStep()
            OnboardingLocationStep()
            OnboardingRulesStep(hasAccepted: Binding<Bool>.constant(false))
            OnboardingNotificationsStep()
        }
        .tempoScreenPadding()
        .padding(.vertical, TempoSpacing.xl)
    }
    .inkBackground()
    .tempoEnvironment(AppEnvironment.demo(signedIn: true, onboarded: false))
}

#Preview("Under 18") {
    UnderageView(canStartOver: true, onStartOver: {}, onSignOut: {})
}
