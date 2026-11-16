import SwiftUI

/// The Passionfruit mark: the fruit cut in half, a wine rind around golden pulp and eight seeds,
/// with a stem and a leaf. The same drawing as the app icon. Use it wherever the brand needs a small sign; never a stock symbol.
///
///     BrandMark(size: 18)
struct BrandMark: View {
    private let size: CGFloat

    init(size: CGFloat = 20) {
        self.size = size
    }

    var body: some View {
        Image("BrandFruit")
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

#Preview("Brand mark") {
    HStack(spacing: 24) {
        BrandMark(size: 18)
        BrandMark(size: 40)
        BrandMark(size: 96)
    }
    .padding()
}
