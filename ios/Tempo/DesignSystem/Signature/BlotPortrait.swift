import SwiftUI

/// A person as a watercolor blot: no circle, no frame. With a photo, the photo is cut to the torn
/// shape of the blot, with the wash showing as a soft rim; without one, their initial sits in the paint.
///
///     BlotPortrait(url: photoURL, name: "Maya", blot: "BuddyRose", size: 148)
struct BlotPortrait: View {
    private let url: URL?
    private let name: String
    private let blot: String
    private let size: CGFloat
    private let turn: Double

    /// The blot images, for picking one per person.
    static let blots: [String] = [
        "BuddyBlush", "BuddySage", "BuddyLilac", "BuddySky", "BuddyButter",
        "BuddyRose", "BuddyMint", "BuddyPeach", "BuddyPeriwinkle", "BuddyCoral"
    ]

    /// A stable blot for a name or id.
    static func blot(for seed: String) -> String {
        var generator = SeededGenerator(seed: seed)
        return generator.pick(BlotPortrait.blots)
    }

    init(url: URL?, name: String, blot: String? = nil, size: CGFloat = 64, turn: Double = 0) {
        self.url = url
        self.name = name
        self.blot = blot ?? BlotPortrait.blot(for: name)
        self.size = size
        self.turn = turn
    }

    /// The wash fills about three quarters of its image, so the image is drawn larger than `size`.
    private var side: CGFloat { size * 1.34 }

    var body: some View {
        ZStack {
            shape
            if url != nil {
                TempoRemoteImage(url: url, name: name, monogramSize: size * 0.4)
                    .frame(width: side * 0.94, height: side * 0.94)
                    .mask { shape.frame(width: side * 0.94, height: side * 0.94) }
            } else {
                Text(TempoRemoteImage.monogramLetter(for: name))
                    .font(Font.system(size: size * 0.42, weight: Font.Weight.medium, design: Font.Design.serif))
                    .foregroundStyle(Color.tempo.textPrimary)
            }
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(name))
    }

    private var shape: some View {
        Image(blot)
            .resizable()
            .frame(width: side, height: side)
            .rotationEffect(Angle.degrees(turn))
    }
}

#Preview("Blot portraits") {
    HStack(spacing: 24) {
        BlotPortrait(url: nil, name: "Maya", size: 96)
        BlotPortrait(url: nil, name: "Theo", size: 64, turn: 40)
    }
    .padding(40)
}
