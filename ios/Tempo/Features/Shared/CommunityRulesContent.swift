import SwiftUI

/// The safety rules, stated plainly. Shown in onboarding (where they must be accepted) and in You.
struct CommunityRulesContent: View {
    @Environment(ConfigStore.self) private var configStore

    init() {}

    private struct Rule: Identifiable {
        let id: Int
        let systemImage: String
        let title: String
        let detail: String
    }

    private var rules: [Rule] {
        let interval: String = TempoFormat.durationPhrase(configStore.frameSampleInterval)
        return [
            Rule(
                id: 0,
                systemImage: "person.badge.shield.checkmark",
                title: String(localized: "Adults only"),
                detail: String(localized: "\(Brand.name) is for people aged \(Birthdate.minimumAge) and over. If someone seems younger, report them.")
            ),
            Rule(
                id: 1,
                systemImage: "video.badge.checkmark",
                title: String(localized: "Video is checked automatically"),
                detail: String(localized: "During a date, a frame from your camera is checked for nudity every \(interval). If nudity is detected, the date ends at once for both of you.")
            ),
            Rule(
                id: 2,
                systemImage: "text.bubble",
                title: String(localized: "Sexual language is not allowed"),
                detail: String(localized: "What you say is turned into text on your phone and checked. The first time you get a warning. The second time in the same date, the date ends.")
            ),
            Rule(
                id: 3,
                systemImage: "exclamationmark.triangle",
                title: String(localized: "Three strikes"),
                detail: String(localized: "Each violation is a strike. Three strikes pause your account while a person reviews it.")
            ),
            Rule(
                id: 4,
                systemImage: "hand.raised",
                title: String(localized: "Leave, report or block anytime"),
                detail: String(localized: "You can leave a date at any moment, no explanation needed. Report and block are on every date and every match. Blocked people are never paired with you again.")
            ),
            Rule(
                id: 5,
                systemImage: "heart",
                title: String(localized: "Be kind"),
                detail: String(localized: "A no is a complete answer. No harassment, no pressure, no recording.")
            )
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(rules) { rule in
                row(rule)
                if rule.id != rules.count - 1 {
                    TempoDivider()
                }
            }
        }
    }

    private func row(_ rule: Rule) -> some View {
        HStack(alignment: .top, spacing: TempoSpacing.md) {
            IconTile(systemName: rule.systemImage, tint: TempoPastel.sage)
            VStack(alignment: .leading, spacing: TempoSpacing.xxs) {
                Text(rule.title)
                    .tempoText(.bodyEmphasis)
                    .foregroundStyle(Color.tempo.textPrimary)
                Text(rule.detail)
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

#Preview("Community rules") {
    ScrollView {
        CommunityRulesContent()
            .tempoScreenPadding()
            .padding(.vertical, TempoSpacing.lg)
    }
    .inkBackground()
    .tempoEnvironment(AppEnvironment.demo())
}
