import SwiftUI

// One preview per `DatePhase`, frozen with Core's `debugSetPhase` on a demo environment.

#if DEBUG
@MainActor
private enum DateFlowPreview {
    static var partner: Partner {
        DemoWorld.roster.first ?? Partner(id: "preview-partner", firstName: "Maya", age: 29, city: "Brooklyn", distanceKm: 2)
    }

    static func turn(isMine: Bool) -> IcebreakerState {
        IcebreakerState(
            question: "What's a small thing that made today better?",
            questionIndex: 0,
            speakerId: isMine ? DemoWorld.demoUserId : partner.id,
            turnEndsAt: Date().addingTimeInterval(21),
            turnDuration: 30,
            isMyTurn: isMine
        )
    }

    static func warning(isFinal: Bool) -> ModerationWarning {
        ModerationWarning(
            id: UUID(),
            category: ModerationCategory.sexualLanguage,
            message: isFinal
                ? "This date was ended because of sexual language."
                : "Keep it respectful. Sexual language will end the date.",
            isFinal: isFinal,
            issuedAt: Date()
        )
    }

    static func screen(
        _ phase: DatePhase,
        showsPartner: Bool = true,
        endsAt: Date? = nil,
        icebreaker: IcebreakerState? = nil,
        countdown: Date? = nil,
        warning: ModerationWarning? = nil
    ) -> some View {
        let environment: AppEnvironment = AppEnvironment.demo()
        environment.dates.debugSetPhase(
            phase,
            partner: showsPartner ? partner : nil,
            endsAt: endsAt,
            icebreaker: icebreaker,
            nextCountdownEndsAt: countdown,
            moderationWarning: warning
        )
        return DateFlowView()
            .tempoEnvironment(environment)
            .preferredColorScheme(.light)
    }

    static var soon: Date {
        Date().addingTimeInterval(3)
    }
}

#Preview("Searching") {
    DateFlowPreview.screen(DatePhase.searching, showsPartner: false)
}

#Preview("Connecting") {
    DateFlowPreview.screen(DatePhase.connecting(partner: DateFlowPreview.partner))
}

#Preview("Live · their turn") {
    DateFlowPreview.screen(
        DatePhase.live,
        endsAt: Date().addingTimeInterval(192),
        icebreaker: DateFlowPreview.turn(isMine: false)
    )
}

#Preview("Live · my turn, final seconds") {
    DateFlowPreview.screen(
        DatePhase.live,
        endsAt: Date().addingTimeInterval(14),
        icebreaker: DateFlowPreview.turn(isMine: true)
    )
}

#Preview("Live · warning") {
    DateFlowPreview.screen(
        DatePhase.live,
        endsAt: Date().addingTimeInterval(120),
        warning: DateFlowPreview.warning(isFinal: false)
    )
}

#Preview("Deciding") {
    DateFlowPreview.screen(
        DatePhase.deciding(partner: DateFlowPreview.partner, deadline: Date().addingTimeInterval(20))
    )
}

#Preview("Awaiting result") {
    DateFlowPreview.screen(DatePhase.awaitingResult(partner: DateFlowPreview.partner))
}

#Preview("Matched") {
    DateFlowPreview.screen(
        DatePhase.matched(match: Match(id: "preview-match", partner: DateFlowPreview.partner, matchedAt: Date()))
    )
}

#Preview("No match") {
    DateFlowPreview.screen(DatePhase.noMatch(partner: DateFlowPreview.partner), countdown: DateFlowPreview.soon)
}

#Preview("Partner left") {
    DateFlowPreview.screen(DatePhase.partnerLeft(partner: DateFlowPreview.partner), countdown: DateFlowPreview.soon)
}

#Preview("Ended · you left") {
    DateFlowPreview.screen(DatePhase.ended(reason: DateEndReason.youLeft), countdown: DateFlowPreview.soon)
}

#Preview("Ended · their connection") {
    DateFlowPreview.screen(DatePhase.ended(reason: DateEndReason.disconnect), countdown: DateFlowPreview.soon)
}

#Preview("Ended · my connection") {
    DateFlowPreview.screen(DatePhase.ended(reason: DateEndReason.disconnect))
}

#Preview("Ended · moderation") {
    DateFlowPreview.screen(
        DatePhase.ended(reason: DateEndReason.moderation),
        warning: DateFlowPreview.warning(isFinal: true)
    )
}

#Preview("Limit reached") {
    DateFlowPreview.screen(
        DatePhase.limitReached(resetsAt: Date().addingTimeInterval(3 * 3600 + 12 * 60)),
        showsPartner: false
    )
}

#Preview("Suspended") {
    DateFlowPreview.screen(
        DatePhase.suspended(reason: "Your account is paused while we review a report."),
        showsPartner: false
    )
}

#Preview("Call permission issue") {
    CallPermissionView(
        issue: PermissionIssue.cameraAndMicrophone,
        dismissTitle: "Not now",
        onOpenSettings: {},
        onDismiss: {}
    )
    .background {
        InkBackground()
    }
    .preferredColorScheme(.light)
}
#endif
