import SwiftUI
import AppKit

/// In-memory image cache keyed by storage identity (not the presigned URL, which rotates its
/// signature each fetch). This stops the "reloads every few seconds" churn when the message
/// list rebuilds or a new presigned URL comes in for the same object.
final class ImageCache: @unchecked Sendable {
    static let shared = ImageCache()
    private let cache = NSCache<NSString, NSImage>()
    private init() { cache.countLimit = 200 }

    func image(for key: String) -> NSImage? { cache.object(forKey: key as NSString) }
    func store(_ image: NSImage, for key: String) { cache.setObject(image, forKey: key as NSString) }
}

/// Loads an attachment's image once and caches it by its stable storage key, so subsequent
/// re-renders and refreshed presigned URLs are served from memory instead of re-downloaded.
@MainActor
final class AttachmentImageLoader: ObservableObject {
    @Published var image: NSImage?
    @Published var failed = false
    private var loadedKey: String?

    func load(_ attachment: AttachmentModel) {
        let key = attachment.storageKey ?? attachment.id
        if loadedKey == key, image != nil { return }
        loadedKey = key
        failed = false

        if let local = attachment.localData, let img = NSImage(data: local) {
            ImageCache.shared.store(img, for: key)
            image = img
            return
        }
        if let cached = ImageCache.shared.image(for: key) {
            image = cached
            return
        }
        guard let url = attachment.url else { failed = true; return }
        Task { [weak self] in
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                guard let img = NSImage(data: data) else {
                    await MainActor.run { self?.failed = true }
                    return
                }
                ImageCache.shared.store(img, for: key)
                await MainActor.run {
                    if self?.loadedKey == key { self?.image = img }
                }
            } catch {
                await MainActor.run { self?.failed = true }
            }
        }
    }
}
