import SwiftUI

// MARK: - Spacing

/// Spacing scale: 4, 8, 12, 16, 24, 32, 48.
enum TempoSpacing {
    static let xxs: CGFloat = 4
    static let xs: CGFloat = 8
    static let sm: CGFloat = 12
    static let md: CGFloat = 16
    static let lg: CGFloat = 24
    static let xl: CGFloat = 32
    static let xxl: CGFloat = 48

    /// Horizontal padding for every screen's content column.
    static let screen: CGFloat = 24
}

// MARK: - Radius

/// Corner radii: 10 icon tiles, 12 chips, 16 cards, 28 sheets. Buttons are capsules.
enum TempoRadius {
    static let tile: CGFloat = 10
    static let chip: CGFloat = 12
    static let card: CGFloat = 16
    static let sheet: CGFloat = 28
}

// MARK: - Sizes

enum TempoSize {
    /// Minimum hit target.
    static let hitTarget: CGFloat = 44
    /// Height of the large button.
    static let buttonLarge: CGFloat = 54
    /// Height of the regular button.
    static let buttonRegular: CGFloat = 48
    /// Height of the compact button.
    static let buttonCompact: CGFloat = 36
    /// Self-view picture-in-picture size (96 x 136).
    static let pip: CGSize = CGSize(width: 96, height: 136)
    /// Side of a pastel icon tile.
    static let iconTile: CGFloat = 36
    /// Point size of icons in bars.
    static let barIcon: CGFloat = 22
    /// Hairline thickness.
    static let hairline: CGFloat = 1
}

// MARK: - Screen padding

extension View {
    /// The standard horizontal screen padding (24 pt).
    func tempoScreenPadding() -> some View {
        padding(.horizontal, TempoSpacing.screen)
    }
}
