import AppKit
import QuickLookThumbnailing

/// Real content thumbnails (e.g. a PDF's actual first page) instead of just
/// the file's type icon. Adapted from TheBoredTeam/boring.notch's
/// `ThumbnailService` (read via `gh api` per check-reference-apps-first) --
/// dropped its security-scoped-resource handling since Atelier's shelf files
/// are already local copies under its own app support directory, not
/// bookmarked references to files elsewhere.
actor ShelfThumbnailService {
    static let shared = ShelfThumbnailService()

    private var cache: [String: NSImage] = [:]
    private var pendingRequests: [String: Task<NSImage?, Never>] = [:]

    private init() {}

    func thumbnail(for url: URL, size: CGSize) async -> NSImage? {
        let cacheKey = "\(url.path)_\(size.width)x\(size.height)"

        if let cached = cache[cacheKey] {
            return cached
        }
        if let pending = pendingRequests[cacheKey] {
            return await pending.value
        }

        let task = Task<NSImage?, Never> {
            let thumbnail = await Self.generate(for: url, size: size)
            if let thumbnail {
                cache[cacheKey] = thumbnail
            }
            pendingRequests[cacheKey] = nil
            return thumbnail
        }
        pendingRequests[cacheKey] = task
        return await task.value
    }

    private static func generate(for url: URL, size: CGSize) async -> NSImage? {
        let scale = await MainActor.run { NSScreen.main?.backingScaleFactor ?? 2 }
        let request = QLThumbnailGenerator.Request(fileAt: url, size: size, scale: scale, representationTypes: .all)
        request.iconMode = false

        return await withCheckedContinuation { (continuation: CheckedContinuation<NSImage?, Never>) in
            QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { representation, _ in
                guard let cgImage = representation?.cgImage else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height)))
            }
        }
    }
}
