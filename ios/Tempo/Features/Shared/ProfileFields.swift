import SwiftUI

/// "I am" and "I'd like to meet". Used by onboarding and by Edit profile.
struct IdentityFields: View {
    @Binding private var gender: Gender?
    @Binding private var interestedIn: [Gender]

    init(gender: Binding<Gender?>, interestedIn: Binding<[Gender]>) {
        self._gender = gender
        self._interestedIn = interestedIn
    }

    var body: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.lg) {
            FieldSection(String(localized: "I am")) {
                SingleChoiceChips(options: Gender.allCases, selection: $gender, allowsClearing: false) { (option: Gender) -> String in
                    option.displayName
                }
            }
            FieldSection(
                String(localized: "I'd like to meet"),
                footnote: String(localized: "Choose everyone you're open to.")
            ) {
                MultiChoiceChips(options: Gender.allCases, selection: $interestedIn) { (option: Gender) -> String in
                    option.pluralDisplayName
                }
            }
        }
    }
}

/// The optional basics that power the dealbreaker filters. Used by onboarding and by Edit profile.
/// `clearable` lists the answers that may be switched back to "no answer".
struct BasicsFields: View {
    @Binding private var intention: Intention?
    @Binding private var children: ChildrenStatus?
    @Binding private var religion: Religion?
    @Binding private var education: Education?
    @Binding private var smoking: Smoking?
    @Binding private var drinking: Drinking?
    private let clearable: Set<DealbreakerKind>

    init(
        intention: Binding<Intention?>,
        children: Binding<ChildrenStatus?>,
        religion: Binding<Religion?>,
        education: Binding<Education?>,
        smoking: Binding<Smoking?>,
        drinking: Binding<Drinking?>,
        clearable: Set<DealbreakerKind> = Set(DealbreakerKind.allCases)
    ) {
        self._intention = intention
        self._children = children
        self._religion = religion
        self._education = education
        self._smoking = smoking
        self._drinking = drinking
        self.clearable = clearable
    }

    var body: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.xl) {
            intentionSection
            childrenSection
            religionSection
            educationSection
            smokingSection
            drinkingSection
        }
    }

    private var intentionSection: some View {
        FieldSection(String(localized: "Looking for"), systemImage: DealbreakerKind.intention.systemImage, tile: DealbreakerKind.intention.tile) {
            SingleChoiceChips(
                options: Intention.allCases,
                selection: $intention,
                allowsClearing: clearable.contains(DealbreakerKind.intention)
            ) { (option: Intention) -> String in
                option.displayName
            }
        }
    }

    private var childrenSection: some View {
        FieldSection(String(localized: "Children"), systemImage: DealbreakerKind.children.systemImage, tile: DealbreakerKind.children.tile) {
            SingleChoiceChips(
                options: ChildrenStatus.allCases,
                selection: $children,
                allowsClearing: clearable.contains(DealbreakerKind.children)
            ) { (option: ChildrenStatus) -> String in
                option.displayName
            }
        }
    }

    private var religionSection: some View {
        FieldSection(String(localized: "Religion"), systemImage: DealbreakerKind.religion.systemImage, tile: DealbreakerKind.religion.tile) {
            SingleChoiceChips(
                options: Religion.allCases,
                selection: $religion,
                allowsClearing: clearable.contains(DealbreakerKind.religion)
            ) { (option: Religion) -> String in
                option.displayName
            }
        }
    }

    private var educationSection: some View {
        FieldSection(String(localized: "Education"), systemImage: DealbreakerKind.education.systemImage, tile: DealbreakerKind.education.tile) {
            SingleChoiceChips(
                options: Education.allCases,
                selection: $education,
                allowsClearing: clearable.contains(DealbreakerKind.education)
            ) { (option: Education) -> String in
                option.displayName
            }
        }
    }

    private var smokingSection: some View {
        FieldSection(String(localized: "Smoking"), systemImage: DealbreakerKind.smoking.systemImage, tile: DealbreakerKind.smoking.tile) {
            SingleChoiceChips(
                options: Smoking.allCases,
                selection: $smoking,
                allowsClearing: clearable.contains(DealbreakerKind.smoking)
            ) { (option: Smoking) -> String in
                option.displayName
            }
        }
    }

    private var drinkingSection: some View {
        FieldSection(String(localized: "Drinking"), systemImage: DealbreakerKind.drinking.systemImage, tile: DealbreakerKind.drinking.tile) {
            SingleChoiceChips(
                options: Drinking.allCases,
                selection: $drinking,
                allowsClearing: clearable.contains(DealbreakerKind.drinking)
            ) { (option: Drinking) -> String in
                option.displayName
            }
        }
    }
}

/// The short bio field with its character limit.
struct BioField: View {
    static let characterLimit: Int = 200

    @Binding private var text: String

    init(text: Binding<String>) {
        self._text = text
    }

    var body: some View {
        TempoTextField(
            String(localized: "About you"),
            text: $text,
            // One short sentence: a TextField prompt never wraps, so a longer one is cut off.
            prompt: String(localized: "Good at ordering for the table."),
            axis: Axis.vertical,
            characterLimit: BioField.characterLimit
        )
    }
}

/// Explains a blocked camera or microphone and offers the way to Settings.
struct PermissionIssueCard: View {
    private let issue: PermissionIssue
    private let onOpenSettings: () -> Void
    private let onDismiss: () -> Void

    init(issue: PermissionIssue, onOpenSettings: @escaping () -> Void, onDismiss: @escaping () -> Void) {
        self.issue = issue
        self.onOpenSettings = onOpenSettings
        self.onDismiss = onDismiss
    }

    var body: some View {
        TempoCard(kind: TempoCardKind.outlined, padding: TempoSpacing.md) {
            VStack(alignment: .leading, spacing: TempoSpacing.sm) {
                HStack(alignment: .center, spacing: TempoSpacing.sm) {
                    IconTile(systemName: "video.slash", tone: TempoTone.amber)
                    Text(issue.title)
                        .tempoText(.bodyEmphasis)
                        .foregroundStyle(Color.tempo.textPrimary)
                }
                Text(issue.message)
                    .tempoText(.secondary)
                    .foregroundStyle(Color.tempo.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: TempoSpacing.xs) {
                    TempoButton(
                        String(localized: "Open Settings"),
                        variant: TempoButtonVariant.secondary,
                        size: TempoButtonSize.regular,
                        fullWidth: false,
                        action: onOpenSettings
                    )
                    TempoButton(
                        String(localized: "Not now"),
                        variant: TempoButtonVariant.ghost,
                        size: TempoButtonSize.regular,
                        fullWidth: false,
                        action: onDismiss
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .contain)
    }
}
