import SwiftUI

/// Edit profile: photos, name, bio, city, identity and the basics. It reuses the onboarding
/// editors. Photos and "use my location" save at once (Core does that); the rest saves with Save.
struct EditProfileView: View {
    @Environment(SessionStore.self) private var session
    @Environment(AppRouter.self) private var router
    @Environment(\.dismiss) private var dismiss

    @State private var form: ProfileForm = ProfileForm()
    @State private var hasLoaded: Bool = false
    @State private var isSaving: Bool = false
    @State private var failure: String?
    @State private var tasks: TaskBag = TaskBag()

    init() {}

    private var original: ProfileForm {
        ProfileForm(user: session.user)
    }

    private var hasChanges: Bool {
        hasLoaded && form.normalised != original.normalised
    }

    private var canSave: Bool {
        hasChanges && form.isValid && !isSaving
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TempoSpacing.xl) {
                ScreenHeader(
                    eyebrow: String(localized: "You"),
                    title: String(localized: "Your"),
                    emphasis: String(localized: "profile.")
                )
                if let failure {
                    ErrorBanner(message: failure, onRetry: { save() }, onDismiss: { self.failure = nil })
                }
                photos
                about
                EditProfileLocation(city: $form.city)
                IdentityFields(gender: $form.gender, interestedIn: $form.interestedIn)
                basics
                ageNote
            }
            .tempoScreenPadding()
            .padding(.vertical, TempoSpacing.lg)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) {
            footer
        }
        .inkBackground()
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .onAppear {
            load()
        }
        .onChange(of: session.user?.city) { _, newCity in
            adoptDetectedCity(newCity)
        }
        .onDisappear {
            tasks.cancelAll()
        }
    }

    // MARK: Sections

    private var photos: some View {
        FieldSection(String(localized: "Photos")) {
            PhotoGridEditor()
        }
    }

    private var about: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.lg) {
            TempoTextField(
                String(localized: "First name"),
                text: $form.firstName,
                errorMessage: form.nameError,
                characterLimit: 30
            )
            .textContentType(.givenName)
            .textInputAutocapitalization(.words)
            .autocorrectionDisabled(true)
            BioField(text: $form.bio)
        }
    }

    private var basics: some View {
        BasicsFields(
            intention: $form.intention,
            children: $form.children,
            religion: $form.religion,
            education: $form.education,
            smoking: $form.smoking,
            drinking: $form.drinking
        )
    }

    @ViewBuilder
    private var ageNote: some View {
        if let age = session.user?.age {
            Text("You're \(age). Your date of birth can't be changed here; contact support if it's wrong.")
                .tempoText(.caption)
                .foregroundStyle(Color.tempo.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var footer: some View {
        TempoButton(String(localized: "Save"), isLoading: isSaving, action: { save() })
            .disabled(!canSave)
            .tempoScreenPadding()
            .padding(.top, TempoSpacing.xs)
            .padding(.bottom, TempoSpacing.xs)
            .background {
                Color.tempo.background
                    .ignoresSafeArea(edges: Edge.Set.bottom)
            }
    }

    // MARK: Actions

    private func load() {
        guard !hasLoaded else { return }
        form = original
        hasLoaded = true
    }

    /// "Use my location" saves the new city straight to the profile; show it in the field too.
    private func adoptDetectedCity(_ newCity: String?) {
        guard hasLoaded, let newCity, !newCity.isEmpty else { return }
        form.city = newCity
    }

    private func save() {
        guard canSave, let user = session.user else { return }
        failure = nil
        let update: ProfileUpdate = form.normalised.update(from: user)
        tasks.run("save") {
            isSaving = true
            let saved: Bool = await session.updateProfile(update)
            isSaving = false
            if Task.isCancelled {
                return
            }
            if saved {
                router.showMessage(String(localized: "Profile saved."), systemImage: "checkmark.circle")
                dismiss()
            } else {
                failure = session.lastError?.userMessage ?? String(localized: "That didn't save. Try again.")
                session.lastError = nil
            }
        }
    }
}

// MARK: - Location

/// City field plus "Use my location". After onboarding, Core saves a detected location at once.
private struct EditProfileLocation: View {
    @Binding var city: String

    @Environment(SessionStore.self) private var session
    @State private var failure: String?
    @State private var tasks: TaskBag = TaskBag()

    var body: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.sm) {
            TempoTextField(
                String(localized: "City"),
                text: $city,
                prompt: String(localized: "Where are you based?"),
                systemImage: "mappin.and.ellipse",
                errorMessage: failure,
                characterLimit: 60
            )
            .textContentType(.addressCity)
            .textInputAutocapitalization(.words)
            TempoButton(
                String(localized: "Use my location"),
                systemImage: "location",
                variant: TempoButtonVariant.secondary,
                size: TempoButtonSize.regular,
                fullWidth: false,
                isLoading: session.isLocating,
                action: { detect() }
            )
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

// MARK: - Form model

/// The editable part of the profile, as plain values.
struct ProfileForm: Equatable {
    var firstName: String = ""
    var bio: String = ""
    var city: String = ""
    var gender: Gender?
    var interestedIn: [Gender] = []
    var intention: Intention?
    var children: ChildrenStatus?
    var religion: Religion?
    var education: Education?
    var smoking: Smoking?
    var drinking: Drinking?

    init() {}

    init(user: User?) {
        guard let user else { return }
        firstName = user.firstName
        bio = user.bio
        city = user.city
        gender = user.gender
        interestedIn = user.interestedIn
        intention = user.intention
        children = user.children
        religion = user.religion
        education = user.education
        smoking = user.smoking
        drinking = user.drinking
    }

    /// The same form with whitespace trimmed, for comparing and saving.
    var normalised: ProfileForm {
        var copy: ProfileForm = self
        copy.firstName = firstName.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.bio = bio.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.city = city.trimmingCharacters(in: .whitespacesAndNewlines)
        return copy
    }

    private var isNameValid: Bool {
        let count: Int = firstName.trimmingCharacters(in: .whitespacesAndNewlines).count
        return count >= 2 && count <= 30
    }

    var nameError: String? {
        isNameValid ? nil : String(localized: "Use between 2 and 30 characters.")
    }

    var isValid: Bool {
        isNameValid && gender != nil && !interestedIn.isEmpty
    }

    /// Only the fields that differ from `user`. A basic whose answer was removed (tap the
    /// selected chip again) is named in `clearing`, which the server receives as `null`.
    func update(from user: User) -> ProfileUpdate {
        var update: ProfileUpdate = ProfileUpdate()
        if firstName != user.firstName { update.firstName = firstName }
        if bio != user.bio { update.bio = bio }
        if city != user.city { update.city = city }
        if gender != user.gender { update.gender = gender }
        if interestedIn != user.interestedIn { update.interestedIn = interestedIn }
        if intention != user.intention { update.intention = intention }
        if children != user.children { update.children = children }
        if religion != user.religion { update.religion = religion }
        if education != user.education { update.education = education }
        if smoking != user.smoking { update.smoking = smoking }
        if drinking != user.drinking { update.drinking = drinking }
        var cleared: Set<ClearableProfileField> = []
        if intention == nil && user.intention != nil { cleared.insert(ClearableProfileField.intention) }
        if children == nil && user.children != nil { cleared.insert(ClearableProfileField.children) }
        if religion == nil && user.religion != nil { cleared.insert(ClearableProfileField.religion) }
        if education == nil && user.education != nil { cleared.insert(ClearableProfileField.education) }
        if smoking == nil && user.smoking != nil { cleared.insert(ClearableProfileField.smoking) }
        if drinking == nil && user.drinking != nil { cleared.insert(ClearableProfileField.drinking) }
        update.clearing = cleared
        return update
    }
}

#Preview("Edit profile") {
    NavigationStack {
        EditProfileView()
    }
    .environment(AppRouter())
    .tempoEnvironment(AppEnvironment.demo())
}
