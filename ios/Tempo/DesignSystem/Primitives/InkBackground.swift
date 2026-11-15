import SwiftUI

/// The app's base background: plain white, edge to edge. Nothing else: no texture, no tint.
/// (The name is kept from v1, where the background was ink.)
/// Put it at the bottom of a `ZStack`, or call `.inkBackground()`.
///
///     ZStack { InkBackground(); content }
struct InkBackground: View {
    init() {}

    var body: some View {
        Color.tempo.background
            .ignoresSafeArea()
            .accessibilityHidden(true)
    }
}

extension View {
    /// Puts the white page background behind this view: `content.inkBackground()`.
    func inkBackground() -> some View {
        background { InkBackground() }
    }
}

#Preview("InkBackground") {
    VStack(alignment: .leading, spacing: TempoSpacing.sm) {
        Text("Daylight").tempoText(.displayS, color: Color.tempo.textPrimary)
        Text("White, black type, one warm accent.").tempoText(.body, color: Color.tempo.textSecondary)
    }
    .tempoScreenPadding()
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .inkBackground()
}
