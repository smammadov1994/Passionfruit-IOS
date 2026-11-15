import SwiftUI
import UIKit

/// The user's own camera. Drop it in anywhere; it takes the video service from the environment.
/// Size, clip and mirror nothing yourself: the front camera is already mirrored.
struct LocalVideoView: View {
    @Environment(AppEnvironment.self) private var environment

    init() {}

    var body: some View {
        VideoSurface(kind: .local, service: environment.video)
    }
}

/// The other person's video (aspect-fill). Drop it in anywhere; it takes the video service from the environment.
struct RemoteVideoView: View {
    @Environment(AppEnvironment.self) private var environment

    init() {}

    var body: some View {
        VideoSurface(kind: .remote, service: environment.video)
    }
}

struct VideoSurface: UIViewRepresentable {
    enum Kind {
        case local
        case remote
    }

    let kind: Kind
    let service: any VideoCallService

    func makeUIView(context: Context) -> UIView {
        switch kind {
        case .local:
            return service.makeLocalVideoView()
        case .remote:
            return service.makeRemoteVideoView()
        }
    }

    func updateUIView(_ uiView: UIView, context: Context) {}

    /// SwiftUI is done with the surface: let the service detach it from its video track.
    static func dismantleUIView(_ uiView: UIView, coordinator: Void) {
        if let surface = uiView as? any ReleasableVideoSurface {
            surface.releaseVideoSurface()
        }
    }
}

/// A video surface that must be detached from its source when SwiftUI removes it.
@MainActor
protocol ReleasableVideoSurface: AnyObject {
    func releaseVideoSurface()
}
