import Foundation
import Observation
import UIKit

/// Memory cache plus de-duplicated downloads for remote photos.
final class ImageCache: @unchecked Sendable {
    private let cache = NSCache<NSString, UIImage>()
    private let session: URLSession
    private let baseURL: URL?

    /// `baseURL` resolves relative photo paths (e.g. `/uploads/a.jpg`) returned by the API.
    init(baseURL: URL? = nil) {
        self.baseURL = baseURL
        let configuration = URLSessionConfiguration.default
        configuration.requestCachePolicy = .returnCacheDataElseLoad
        configuration.urlCache = URLCache(memoryCapacity: 16 * 1024 * 1024, diskCapacity: 128 * 1024 * 1024)
        self.session = URLSession(configuration: configuration)
        cache.countLimit = 200
    }

    /// Turns a photo URL string from the API into a loadable URL.
    func resolve(_ string: String?) -> URL? {
        guard let string, !string.isEmpty else { return nil }
        if let url = URL(string: string), url.scheme != nil {
            return url
        }
        if let baseURL {
            return URL(string: string, relativeTo: baseURL)?.absoluteURL
        }
        return nil
    }

    func cachedImage(for url: URL) -> UIImage? {
        cache.object(forKey: url.absoluteString as NSString)
    }

    func image(for url: URL) async throws -> UIImage {
        if let cached = cachedImage(for: url) {
            return cached
        }
        let data: Data
        if url.isFileURL {
            do {
                data = try Data(contentsOf: url)
            } catch {
                throw TempoError.unknown("")
            }
        } else {
            do {
                let (body, response) = try await session.data(from: url)
                if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                    throw TempoError.server(status: http.statusCode, code: "image_load_failed", message: "")
                }
                data = body
            } catch {
                throw TempoError.from(error)
            }
        }
        guard let image = UIImage(data: data) else {
            throw TempoError.decoding
        }
        cache.setObject(image, forKey: url.absoluteString as NSString)
        return image
    }
}

/// View-model for one remote image. Create it in a view with `@State` and call `load` from `.task(id:)`.
@MainActor
@Observable
final class RemoteImageLoader {
    enum Phase: Equatable {
        case empty
        case loading
        case loaded
        case failed
    }

    private(set) var image: UIImage?
    private(set) var phase: Phase = .empty

    @ObservationIgnored private var currentURL: URL?

    init() {}

    /// Loads `urlString` through `cache`. A nil or unusable string leaves the loader `.empty`
    /// so the view shows its monogram placeholder.
    func load(_ urlString: String?, using cache: ImageCache) async {
        guard let url = cache.resolve(urlString) else {
            currentURL = nil
            image = nil
            phase = .empty
            return
        }
        if url == currentURL && phase == .loaded {
            return
        }
        currentURL = url
        if let cached = cache.cachedImage(for: url) {
            image = cached
            phase = .loaded
            return
        }
        phase = .loading
        do {
            let loaded: UIImage = try await cache.image(for: url)
            guard currentURL == url else { return }
            image = loaded
            phase = .loaded
        } catch {
            guard currentURL == url else { return }
            image = nil
            phase = .failed
        }
    }
}

enum ImageEncoding {
    /// Scales a picked photo down to `maxSide` and encodes it as JPEG for `POST /v1/me/photos`.
    @MainActor
    static func jpegData(from image: UIImage, maxSide: CGFloat = 1440, quality: CGFloat = 0.82) -> Data? {
        let size: CGSize = image.size
        let longest: CGFloat = max(size.width, size.height)
        guard longest > 0 else { return nil }
        let scale: CGFloat = min(1, maxSide / longest)
        let target = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: target, format: format)
        let scaled: UIImage = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        return scaled.jpegData(compressionQuality: quality)
    }
}
