import PhotosUI
import SwiftUI
import UIKit

/// Six 3:4 photo slots with pick, upload progress, retry, remove and "make main".
/// During onboarding it edits `session.draft.photoUrls`; afterwards the profile's photos
/// (Core's `uploadPhoto`, `removePhoto` and `setPhotoOrder` decide which).
struct PhotoGridEditor: View {
    static let maximumPhotos: Int = 6
    static let minimumPhotos: Int = 1

    @Environment(AppEnvironment.self) private var environment
    @Environment(SessionStore.self) private var session

    @State private var isPickerPresented: Bool = false
    @State private var pickedItem: PhotosPickerItem?
    @State private var uploadingImage: UIImage?
    @State private var failedImage: UIImage?
    @State private var failureMessage: String?
    @State private var selectedUrl: String?
    @State private var isBusy: Bool = false
    @State private var tasks: TaskBag = TaskBag()

    init() {}

    private var urls: [String] {
        if session.isOnboardingComplete {
            return session.user?.photoUrls ?? []
        }
        return session.draft.photoUrls
    }

    private var isUploading: Bool {
        uploadingImage != nil
    }

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: TempoSpacing.sm), count: 3)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.sm) {
            if let failureMessage {
                ErrorBanner(
                    message: failureMessage,
                    onRetry: retryAction,
                    onDismiss: { clearFailure() }
                )
            }
            grid
            Text(countLine)
                .tempoText(.caption)
                .foregroundStyle(Color.tempo.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .photosPicker(isPresented: $isPickerPresented, selection: $pickedItem, matching: PHPickerFilter.images)
        .onChange(of: pickedItem) { _, newItem in
            handlePicked(newItem)
        }
        .confirmationDialog(
            Text("Photo"),
            isPresented: dialogBinding,
            titleVisibility: .hidden,
            actions: { dialogActions }
        )
        .onDisappear {
            tasks.cancelAll()
        }
    }

    private var retryAction: (() -> Void)? {
        guard failedImage != nil else { return nil }
        return { retryUpload() }
    }

    private var grid: some View {
        LazyVGrid(columns: columns, spacing: TempoSpacing.sm) {
            ForEach(0..<PhotoGridEditor.maximumPhotos, id: \.self) { index in
                slot(at: index)
            }
        }
        .disabled(isBusy)
    }

    private var countLine: String {
        let count: Int = urls.count
        let maximum: Int = PhotoGridEditor.maximumPhotos
        if count == 0 {
            return String(localized: "Add at least one photo, up to \(maximum). Your face should be easy to see in the first one.")
        }
        return String(localized: "\(count) of \(maximum). The first photo is the one people see.")
    }

    private func slot(at index: Int) -> PhotoSlot {
        let current: [String] = urls
        let isPrimary: Bool = index == 0
        if index < current.count {
            let url: String = current[index]
            return PhotoSlot(
                url: environment.imageCache.resolve(url),
                isPrimary: isPrimary,
                onTap: { selectedUrl = url },
                onRemove: { remove(url) }
            )
        }
        if index == current.count, let uploadingImage {
            return PhotoSlot(
                url: nil,
                image: Image(uiImage: uploadingImage),
                isPrimary: isPrimary,
                isLoading: true,
                onTap: {}
            )
        }
        return PhotoSlot(
            url: nil,
            isPrimary: isPrimary,
            onTap: { openPicker() }
        )
    }

    // MARK: Dialog

    private var dialogBinding: Binding<Bool> {
        Binding<Bool>(
            get: { selectedUrl != nil },
            set: { isPresented in
                if !isPresented {
                    selectedUrl = nil
                }
            }
        )
    }

    @ViewBuilder
    private var dialogActions: some View {
        if let target = selectedUrl {
            if urls.first != target {
                Button(String(localized: "Make main photo")) {
                    makeMain(target)
                }
            }
            Button(String(localized: "Remove photo"), role: .destructive) {
                remove(target)
            }
        }
        Button(String(localized: "Cancel"), role: .cancel) {}
    }

    // MARK: Actions

    private func openPicker() {
        guard !isUploading, urls.count < PhotoGridEditor.maximumPhotos else { return }
        clearFailure()
        isPickerPresented = true
    }

    private func handlePicked(_ item: PhotosPickerItem?) {
        guard let item else { return }
        pickedItem = nil
        tasks.run("upload") {
            await load(item)
        }
    }

    private func load(_ item: PhotosPickerItem) async {
        do {
            let data: Data? = try await item.loadTransferable(type: Data.self)
            guard let data, let image = UIImage(data: data) else {
                failureMessage = String(localized: "Couldn't read that photo. Try another one.")
                return
            }
            await upload(image)
        } catch {
            if !Task.isCancelled {
                failureMessage = String(localized: "Couldn't read that photo. Try another one.")
            }
        }
    }

    private func upload(_ image: UIImage) async {
        failureMessage = nil
        failedImage = nil
        uploadingImage = image
        let uploaded: String? = await session.uploadPhoto(image: image)
        uploadingImage = nil
        if uploaded != nil || Task.isCancelled {
            return
        }
        failedImage = image
        failureMessage = session.lastError?.userMessage ?? String(localized: "That photo didn't upload. Try again.")
        session.lastError = nil
    }

    private func retryUpload() {
        guard let image = failedImage, !isUploading else { return }
        tasks.run("upload") {
            await upload(image)
        }
    }

    private func clearFailure() {
        failureMessage = nil
        failedImage = nil
    }

    private func remove(_ url: String) {
        if session.isOnboardingComplete && urls.count <= PhotoGridEditor.minimumPhotos {
            failedImage = nil
            failureMessage = String(localized: "Keep at least one photo so people can see you.")
            return
        }
        tasks.run("edit") {
            isBusy = true
            let removed: Bool = await session.removePhoto(url: url)
            isBusy = false
            if !removed && !Task.isCancelled {
                reportEditFailure()
            }
        }
    }

    private func makeMain(_ url: String) {
        var reordered: [String] = urls.filter { $0 != url }
        reordered.insert(url, at: 0)
        tasks.run("edit") {
            isBusy = true
            let saved: Bool = await session.setPhotoOrder(reordered)
            isBusy = false
            if !saved && !Task.isCancelled {
                reportEditFailure()
            }
        }
    }

    private func reportEditFailure() {
        failedImage = nil
        failureMessage = session.lastError?.userMessage ?? String(localized: "That didn't save. Try again.")
        session.lastError = nil
    }
}

#Preview("Photo grid") {
    ScrollView {
        PhotoGridEditor()
            .tempoScreenPadding()
            .padding(.vertical, TempoSpacing.lg)
    }
    .inkBackground()
    .tempoEnvironment(AppEnvironment.demo(signedIn: true, onboarded: false))
}
