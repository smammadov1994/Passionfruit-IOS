import AVFoundation
import Foundation
import UIKit

enum PermissionStatus: String, Sendable, Equatable {
    case notDetermined
    case granted
    case denied
}

/// What is stopping the user from going online. Shown by UI with an "Open Settings" action.
enum PermissionIssue: String, Sendable, Equatable, Identifiable {
    case camera
    case microphone
    case cameraAndMicrophone

    var id: String { rawValue }

    var title: String {
        switch self {
        case .camera: return String(localized: "Camera is off")
        case .microphone: return String(localized: "Microphone is off")
        case .cameraAndMicrophone: return String(localized: "Camera and microphone are off")
        }
    }

    var message: String {
        switch self {
        case .camera:
            return String(localized: "\(Brand.name) dates are face to face. Turn on camera access in Settings to go online.")
        case .microphone:
            return String(localized: "Your date needs to hear you. Turn on microphone access in Settings to go online.")
        case .cameraAndMicrophone:
            return String(localized: "\(Brand.name) dates are live video. Turn on camera and microphone access in Settings to go online.")
        }
    }
}

/// Camera and microphone permission, behind a protocol so demo mode and tests never prompt.
@MainActor
protocol MediaPermissions: AnyObject {
    func cameraStatus() -> PermissionStatus
    func microphoneStatus() -> PermissionStatus
    /// Prompts when not determined. Returns whether access is granted.
    func requestCamera() async -> Bool
    /// Prompts when not determined. Returns whether access is granted.
    func requestMicrophone() async -> Bool
}

extension MediaPermissions {
    /// Requests both, camera first. Returns nil when both are granted.
    func requestCameraAndMicrophone() async -> PermissionIssue? {
        let camera: Bool = await requestCamera()
        let microphone: Bool = await requestMicrophone()
        if camera && microphone {
            return nil
        }
        if !camera && !microphone {
            return .cameraAndMicrophone
        }
        return camera ? .microphone : .camera
    }
}

@MainActor
final class LiveMediaPermissions: MediaPermissions {
    init() {}

    func cameraStatus() -> PermissionStatus {
        LiveMediaPermissions.map(AVCaptureDevice.authorizationStatus(for: .video))
    }

    func microphoneStatus() -> PermissionStatus {
        LiveMediaPermissions.map(AVCaptureDevice.authorizationStatus(for: .audio))
    }

    func requestCamera() async -> Bool {
        switch cameraStatus() {
        case .granted:
            return true
        case .denied:
            return false
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .video)
        }
    }

    func requestMicrophone() async -> Bool {
        switch microphoneStatus() {
        case .granted:
            return true
        case .denied:
            return false
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .audio)
        }
    }

    private static func map(_ status: AVAuthorizationStatus) -> PermissionStatus {
        switch status {
        case .authorized:
            return .granted
        case .notDetermined:
            return .notDetermined
        case .denied, .restricted:
            return .denied
        @unknown default:
            return .denied
        }
    }
}

/// Always answers from its two flags. Demo mode uses it so the flow works in the Simulator.
@MainActor
final class MockMediaPermissions: MediaPermissions {
    var cameraGranted: Bool
    var microphoneGranted: Bool

    init(cameraGranted: Bool = true, microphoneGranted: Bool = true) {
        self.cameraGranted = cameraGranted
        self.microphoneGranted = microphoneGranted
    }

    func cameraStatus() -> PermissionStatus {
        cameraGranted ? .granted : .denied
    }

    func microphoneStatus() -> PermissionStatus {
        microphoneGranted ? .granted : .denied
    }

    func requestCamera() async -> Bool {
        cameraGranted
    }

    func requestMicrophone() async -> Bool {
        microphoneGranted
    }
}

enum SystemSettings {
    /// Opens this app's page in the Settings app.
    @MainActor
    static func open() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
    }
}
