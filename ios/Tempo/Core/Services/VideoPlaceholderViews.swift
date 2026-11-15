import AVFoundation
import UIKit

/// Animated stand-in for a video feed: a slow drift between soft, muted mid-tones (warm sand
/// for the remote feed, cool grey-blue for the local one), so white call chrome reads over it
/// the way it does over real footage. No brand color: this is "video", not chrome.
/// Used for the remote feed in demo mode and for the local feed when there is no camera.
final class PlaceholderVideoUIView: UIView {
    enum Style {
        case local
        case remote
    }

    private let style: Style
    private let gradientLayer = CAGradientLayer()

    init(style: Style) {
        self.style = style
        super.init(frame: .zero)
        configure()
    }

    required init?(coder: NSCoder) {
        self.style = .remote
        super.init(coder: coder)
        configure()
    }

    private static func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat) -> CGColor {
        UIColor(red: red / 255, green: green / 255, blue: blue / 255, alpha: 1).cgColor
    }

    private var baseColors: [CGColor] {
        switch style {
        case .remote:
            return [
                PlaceholderVideoUIView.color(168, 152, 140),
                PlaceholderVideoUIView.color(204, 180, 162),
                PlaceholderVideoUIView.color(138, 130, 128)
            ]
        case .local:
            return [
                PlaceholderVideoUIView.color(150, 162, 176),
                PlaceholderVideoUIView.color(188, 196, 206),
                PlaceholderVideoUIView.color(132, 142, 158)
            ]
        }
    }

    private var shiftedColors: [CGColor] {
        switch style {
        case .remote:
            return [
                PlaceholderVideoUIView.color(190, 164, 148),
                PlaceholderVideoUIView.color(150, 140, 136),
                PlaceholderVideoUIView.color(212, 192, 172)
            ]
        case .local:
            return [
                PlaceholderVideoUIView.color(176, 184, 196),
                PlaceholderVideoUIView.color(140, 150, 166),
                PlaceholderVideoUIView.color(196, 202, 210)
            ]
        }
    }

    private func configure() {
        isUserInteractionEnabled = false
        clipsToBounds = true
        // Surface 2 (#EFEBE6), the app's neutral behind anything that has not drawn yet.
        backgroundColor = UIColor(red: 239 / 255, green: 235 / 255, blue: 230 / 255, alpha: 1)

        gradientLayer.colors = baseColors
        gradientLayer.startPoint = CGPoint(x: 0, y: 0)
        gradientLayer.endPoint = CGPoint(x: 1, y: 1)
        layer.addSublayer(gradientLayer)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        gradientLayer.frame = bounds
        CATransaction.commit()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil {
            gradientLayer.removeAllAnimations()
        } else {
            startAnimating()
        }
    }

    private func startAnimating() {
        guard !UIAccessibility.isReduceMotionEnabled else { return }
        guard gradientLayer.animation(forKey: "drift") == nil else { return }

        let drift = CABasicAnimation(keyPath: "colors")
        drift.fromValue = baseColors
        drift.toValue = shiftedColors
        drift.duration = 6
        drift.autoreverses = true
        drift.repeatCount = .infinity
        drift.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        gradientLayer.add(drift, forKey: "drift")
    }
}

/// A view backed by an `AVCaptureVideoPreviewLayer`.
final class CameraPreviewUIView: UIView {
    override class var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }

    var previewLayer: AVCaptureVideoPreviewLayer? {
        layer as? AVCaptureVideoPreviewLayer
    }

    func attach(session: AVCaptureSession) {
        previewLayer?.session = session
        previewLayer?.videoGravity = .resizeAspectFill
    }
}

/// Demo-mode local video: the real camera when there is one, otherwise the placeholder.
final class DemoLocalVideoUIView: UIView {
    private let placeholder = PlaceholderVideoUIView(style: .local)
    private let preview = CameraPreviewUIView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    private func configure() {
        clipsToBounds = true
        placeholder.frame = bounds
        placeholder.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(placeholder)
        preview.frame = bounds
        preview.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        preview.isHidden = true
        addSubview(preview)
    }

    func showCamera(session: AVCaptureSession) {
        preview.attach(session: session)
        preview.isHidden = false
    }

    func showPlaceholder() {
        preview.isHidden = true
    }
}
