import SwiftUI
import UIKit

/// The steps of onboarding, in order.
enum OnboardingStep: Int, CaseIterable, Hashable {
    case name
    case birthdate
    case identity
    case photos
    case bio
    case location
    case basics
    case cameraAndMicrophone
    case rules
    case notifications

    var number: Int { rawValue + 1 }

    var previous: OnboardingStep? { OnboardingStep(rawValue: rawValue - 1) }
    var next: OnboardingStep? { OnboardingStep(rawValue: rawValue + 1) }
}

/// Multi-step onboarding: collects the profile into `session.draft`, primes each permission,
/// has the community rules accepted, then submits through Core.
struct OnboardingFlow: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(SessionStore.self) private var session
    @Environment(DateStore.self) private var dateStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The account that entered an under-18 birthdate on this device. The gate stays shut for it.
    @AppStorage("tempo.onboarding.underageUserId") private var underageUserId: String = ""

    @State private var step: OnboardingStep = OnboardingStep.name
    @State private var pickedBirthdate: Date = OnboardingFlow.defaultBirthdate()
    @State private var hasPickedBirthdate: Bool = false
    @State private var hasAcceptedRules: Bool = false
    @State private var mediaIssue: PermissionIssue?
    @State private var hasAskedForMedia: Bool = false
    @State private var isAskingForMedia: Bool = false
    @State private var wantsNotifications: Bool = false
    @State private var submitError: String?
    @State private var tasks: TaskBag = TaskBag()

    init() {}

    private var isAgeBlocked: Bool {
        guard !underageUserId.isEmpty else { return false }
        return underageUserId == (session.userId ?? "")
    }

    var body: some View {
        Group {
            if isAgeBlocked {
                UnderageView(
                    canStartOver: environment.isDemo,
                    onStartOver: { startOver() },
                    onSignOut: { signOut() }
                )
            } else {
                flow
            }
        }
        .onAppear {
            restoreBirthdate()
        }
        .onDisappear {
            tasks.cancelAll()
        }
    }

    // MARK: Layout

    private var flow: some View {
        VStack(spacing: 0) {
            topBar
            ScrollView {
                stepContent
                    .tempoScreenPadding()
                    .padding(.top, TempoSpacing.md)
                    .padding(.bottom, TempoSpacing.xl)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollDismissesKeyboard(.interactively)
            .scrollBounceBehavior(.basedOnSize)
            .id(step)
            .transition(AnyTransition.tempoReplace(reduceMotion: reduceMotion))
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            footer
        }
        .inkBackground()
    }

    /// The thin black progress line across the top, then Back (or Sign out on the first step).
    private var topBar: some View {
        VStack(spacing: TempoSpacing.xxs) {
            OnboardingProgress(step: step.number, total: OnboardingStep.allCases.count)
                .tempoScreenPadding()
            HStack(spacing: TempoSpacing.sm) {
                backButton
                Spacer(minLength: 0)
                trailingControl
            }
            .padding(.horizontal, TempoSpacing.sm)
            .frame(minHeight: TempoSize.hitTarget)
        }
        .padding(.top, TempoSpacing.xs)
    }

    @ViewBuilder
    private var backButton: some View {
        if step.previous != nil {
            IconCircleButton(
                systemImage: "chevron.left",
                accessibilityLabel: String(localized: "Back"),
                kind: IconCircleButtonKind.plain,
                size: TempoSize.hitTarget,
                action: { goBack() }
            )
            .disabled(session.isWorking)
        }
    }

    @ViewBuilder
    private var trailingControl: some View {
        if step.previous == nil {
            TempoButton(
                String(localized: "Sign out"),
                variant: TempoButtonVariant.ghost,
                size: TempoButtonSize.compact,
                fullWidth: false,
                action: { signOut() }
            )
        }
    }

    // MARK: Steps

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case .name:
            OnboardingNameStep(onSubmit: { advance() })
        case .birthdate:
            OnboardingBirthdateStep(date: $pickedBirthdate, hasPicked: $hasPickedBirthdate)
        case .identity:
            OnboardingIdentityStep()
        case .photos:
            OnboardingPhotosStep()
        case .bio:
            OnboardingBioStep()
        case .location:
            OnboardingLocationStep()
        case .basics:
            OnboardingBasicsStep()
        case .cameraAndMicrophone:
            OnboardingMediaStep(issue: mediaIssue, hasAsked: hasAskedForMedia, onDismissIssue: { mediaIssue = nil })
        case .rules:
            OnboardingRulesStep(hasAccepted: $hasAcceptedRules)
        case .notifications:
            OnboardingNotificationsStep()
        }
    }

    // MARK: Footer

    private var footer: some View {
        VStack(spacing: TempoSpacing.xs) {
            if let submitError {
                ErrorBanner(
                    message: submitError,
                    onRetry: { submit(notify: wantsNotifications) },
                    onDismiss: { self.submitError = nil }
                )
            }
            TempoButton(primaryTitle, isLoading: isPrimaryLoading, action: { primaryAction() })
                .disabled(!canContinue)
            if let secondaryTitle {
                TempoButton(
                    secondaryTitle,
                    variant: TempoButtonVariant.ghost,
                    size: TempoButtonSize.regular,
                    action: { secondaryAction() }
                )
                .disabled(session.isWorking || isAskingForMedia)
            }
        }
        .tempoScreenPadding()
        .padding(.top, TempoSpacing.xs)
        .padding(.bottom, TempoSpacing.xs)
        .background {
            Color.tempo.background
                .ignoresSafeArea(edges: Edge.Set.bottom)
        }
    }

    private var hasChosenBasics: Bool {
        let draft: OnboardingDraft = session.draft
        return draft.intention != nil || draft.children != nil || draft.religion != nil
            || draft.education != nil || draft.smoking != nil || draft.drinking != nil
    }

    private var primaryTitle: String {
        switch step {
        case .name, .birthdate, .identity, .photos, .location:
            return String(localized: "Continue")
        case .bio:
            let isEmpty: Bool = session.draft.bio.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            return isEmpty ? String(localized: "Skip for now") : String(localized: "Continue")
        case .basics:
            return hasChosenBasics ? String(localized: "Continue") : String(localized: "Skip for now")
        case .cameraAndMicrophone:
            return hasAskedForMedia ? String(localized: "Continue") : String(localized: "Allow camera and microphone")
        case .rules:
            return String(localized: "I agree")
        case .notifications:
            return String(localized: "Turn on notifications")
        }
    }

    private var secondaryTitle: String? {
        switch step {
        case .name, .birthdate, .identity, .photos, .bio, .location, .basics, .rules:
            return nil
        case .cameraAndMicrophone:
            return hasAskedForMedia ? nil : String(localized: "Not now")
        case .notifications:
            return String(localized: "Not now")
        }
    }

    private var isPrimaryLoading: Bool {
        switch step {
        case .name, .birthdate, .identity, .bio, .location, .basics, .rules:
            return false
        case .photos:
            return false
        case .cameraAndMicrophone:
            return isAskingForMedia
        case .notifications:
            return session.isWorking
        }
    }

    private var canContinue: Bool {
        let draft: OnboardingDraft = session.draft
        switch step {
        case .name:
            return draft.isNameValid
        case .birthdate:
            return hasPickedBirthdate
        case .identity:
            return draft.gender != nil && !draft.interestedIn.isEmpty
        case .photos:
            return draft.photoUrls.count >= PhotoGridEditor.minimumPhotos && !session.isUploadingPhoto
        case .bio, .basics:
            return true
        case .location:
            return !draft.city.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !session.isLocating
        case .cameraAndMicrophone:
            return !isAskingForMedia
        case .rules:
            return hasAcceptedRules
        case .notifications:
            return !session.isWorking
        }
    }

    // MARK: Actions

    private func primaryAction() {
        guard canContinue else { return }
        switch step {
        case .name, .identity, .photos, .bio, .location, .basics, .rules:
            advance()
        case .birthdate:
            confirmBirthdate()
        case .cameraAndMicrophone:
            if hasAskedForMedia {
                advance()
            } else {
                askForMedia()
            }
        case .notifications:
            submit(notify: true)
        }
    }

    private func secondaryAction() {
        switch step {
        case .name, .birthdate, .identity, .photos, .bio, .location, .basics, .rules:
            break
        case .cameraAndMicrophone:
            advance()
        case .notifications:
            submit(notify: false)
        }
    }

    private func advance() {
        guard canContinue, let next = step.next else { return }
        move(to: next)
    }

    private func goBack() {
        guard let previous = step.previous else { return }
        submitError = nil
        move(to: previous)
    }

    private func move(to newStep: OnboardingStep) {
        OnboardingFlow.dismissKeyboard()
        session.lastError = nil
        withAnimation(Animation.tempo.standard(reduceMotion: reduceMotion)) {
            step = newStep
        }
    }

    /// The 18+ gate. An under-18 birthdate closes onboarding for this account on this device.
    private func confirmBirthdate() {
        session.draft.birthdate = pickedBirthdate
        if session.draft.isAdult {
            advance()
        } else {
            OnboardingFlow.dismissKeyboard()
            underageUserId = session.userId ?? ""
        }
    }

    private func askForMedia() {
        tasks.run("media") {
            isAskingForMedia = true
            let issue: PermissionIssue? = await dateStore.requestMediaAccess()
            isAskingForMedia = false
            mediaIssue = issue
            hasAskedForMedia = true
        }
    }

    private func submit(notify: Bool) {
        wantsNotifications = notify
        session.draft.notifyOnlineSingles = notify
        submitError = nil
        tasks.run("submit") {
            let finished: Bool = await session.submitOnboarding()
            if finished || Task.isCancelled {
                return
            }
            submitError = session.lastError?.userMessage ?? String(localized: "That didn't go through. Try again.")
            session.lastError = nil
        }
    }

    private func signOut() {
        tasks.run("signOut") {
            await session.signOut()
        }
    }

    /// Demo builds only: lets a tester leave the under-18 screen.
    private func startOver() {
        underageUserId = ""
        session.draft.birthdate = nil
        hasPickedBirthdate = false
        pickedBirthdate = OnboardingFlow.defaultBirthdate()
        step = OnboardingStep.birthdate
    }

    private func restoreBirthdate() {
        if let saved = session.draft.birthdate {
            pickedBirthdate = saved
            hasPickedBirthdate = true
        }
    }

    // MARK: Helpers

    /// Where the wheels start. The date must still be changed before Continue is enabled,
    /// so nobody passes the age gate without entering a birthdate.
    static func defaultBirthdate(now: Date = Date(), calendar: Calendar = Calendar.current) -> Date {
        calendar.date(byAdding: .year, value: -25, to: now) ?? now
    }

    @MainActor
    static func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

#Preview("Onboarding") {
    OnboardingFlow()
        .tempoEnvironment(AppEnvironment.demo(signedIn: true, onboarded: false))
}
