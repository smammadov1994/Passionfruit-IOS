import SwiftUI

// MARK: - TempoRemoteImage

/// A remote photo that fills whatever frame it is given, over a deterministic per-name pastel
/// with a near-black serif monogram. The pastel stays underneath while the photo loads and when
/// it fails, so there is never an empty box. Loading goes through `AsyncImage`,
/// which uses `URLSession.shared` and therefore `URLCache.shared`.
///
///     TempoRemoteImage(url: partner.photoUrl, name: partner.firstName, monogramSize: 64)
///         .frame(height: 320).clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
struct TempoRemoteImage: View {
    private let url: URL?
    private let name: String
    private let monogramSize: CGFloat

    init(url: URL?, name: String, monogramSize: CGFloat = 40) {
        self.url = url
        self.name = name
        self.monogramSize = monogramSize
    }

    var body: some View {
        fallback
            .overlay { remote }
            .clipped()
    }

    private var fallback: some View {
        TempoPastel.deterministic(for: name).color
            .overlay { monogram }
    }

    @ViewBuilder
    private var monogram: some View {
        let letter: String = TempoRemoteImage.monogramLetter(for: name)
        if letter.isEmpty {
            Image(systemName: "person")
                .font(Font.system(size: monogramSize * 0.8, weight: Font.Weight.light))
                .foregroundStyle(Color.tempo.textPrimary)
        } else {
            Text(letter)
                .font(Font.system(size: monogramSize, weight: Font.Weight.medium, design: Font.Design.serif))
                .foregroundStyle(Color.tempo.textPrimary)
        }
    }

    @ViewBuilder
    private var remote: some View {
        if let url {
            AsyncImage(url: url, transaction: Transaction(animation: Animation.tempo.fade)) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                        .transition(AnyTransition.opacity)
                case .empty:
                    Color.clear
                case .failure:
                    Color.clear
                @unknown default:
                    Color.clear
                }
            }
        }
    }

    /// The first letter of `name`, uppercased; empty when there is none.
    static func monogramLetter(for name: String) -> String {
        let trimmed: String = name.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        guard let first = trimmed.first else { return "" }
        return String(first).uppercased()
    }
}

// MARK: - AvatarView

/// Ring around an avatar.
enum AvatarRing: Hashable {
    case none
    /// A hairline, to separate the photo from the page.
    case hairline
    /// Thin accent ring: unread, new match, the partner in a key moment.
    case ember
    /// Thin ochre ring: premium member.
    case gold
}

/// A circular avatar with a monogram fallback.
///
///     AvatarView(url: match.partner.photoUrl, name: match.partner.firstName, size: 56, ring: .ember)
struct AvatarView: View {
    private let url: URL?
    private let name: String
    private let size: CGFloat
    private let ring: AvatarRing
    private let showsOnlineDot: Bool

    init(url: URL?, name: String, size: CGFloat = 56, ring: AvatarRing = AvatarRing.none, showsOnlineDot: Bool = false) {
        self.url = url
        self.name = name
        self.size = size
        self.ring = ring
        self.showsOnlineDot = showsOnlineDot
    }

    var body: some View {
        TempoRemoteImage(url: url, name: name, monogramSize: size * 0.42)
            .frame(width: size, height: size)
            .clipShape(Circle())
            .overlay { ringView }
            .overlay(alignment: .bottomTrailing) { onlineDot }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(name))
            .accessibilityAddTraits(AccessibilityTraits.isImage)
    }

    private var ringWidth: CGFloat {
        size >= 96 ? 2.0 : 1.5
    }

    @ViewBuilder
    private var ringView: some View {
        switch ring {
        case .none:
            EmptyView()
        case .hairline:
            Circle().strokeBorder(Color.tempo.hairline, lineWidth: 1)
        case .ember:
            Circle()
                .strokeBorder(Color.tempo.accent, lineWidth: ringWidth)
                .padding(-(ringWidth + 3.0))
        case .gold:
            Circle()
                .strokeBorder(Color.tempo.premium, lineWidth: ringWidth)
                .padding(-(ringWidth + 3.0))
        }
    }

    @ViewBuilder
    private var onlineDot: some View {
        if showsOnlineDot {
            let dot: CGFloat = max(10.0, size * 0.22)
            Circle()
                .fill(Color.tempo.mint)
                .frame(width: dot, height: dot)
                .overlay { Circle().strokeBorder(Color.tempo.background, lineWidth: 2) }
        }
    }
}

#Preview("Avatars") {
    VStack(spacing: TempoSpacing.lg) {
        HStack(spacing: TempoSpacing.md) {
            AvatarView(url: nil, name: "Maya", size: 72, ring: AvatarRing.ember)
            AvatarView(url: nil, name: "Jonas", size: 72, ring: AvatarRing.gold)
            AvatarView(url: nil, name: "Ines", size: 72, ring: AvatarRing.hairline, showsOnlineDot: true)
            AvatarView(url: nil, name: "", size: 72)
        }
        TempoRemoteImage(url: nil, name: "Theo", monogramSize: 72)
            .frame(width: 220, height: 280)
            .clipShape(RoundedRectangle(cornerRadius: TempoRadius.card, style: .continuous))
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .inkBackground()
}
