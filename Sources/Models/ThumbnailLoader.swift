import AppKit
import QuickLookThumbnailing

/// Gera thumbnails via Quick Look com cache em memória.
final class ThumbnailLoader {
    static let shared = ThumbnailLoader()

    private let cache = NSCache<NSURL, NSImage>()

    private init() {
        cache.countLimit = 600
    }

    func thumbnail(for url: URL, size: CGSize) async -> NSImage? {
        if let cached = cache.object(forKey: url as NSURL) {
            return cached
        }

        let scale = await MainActor.run { NSScreen.main?.backingScaleFactor ?? 2 }
        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: size,
            scale: scale,
            representationTypes: .thumbnail
        )

        guard let representation = try? await QLThumbnailGenerator.shared
            .generateBestRepresentation(for: request)
        else {
            return nil
        }

        let image = representation.nsImage
        cache.setObject(image, forKey: url as NSURL)
        return image
    }

    func invalidate(_ url: URL) {
        cache.removeObject(forKey: url as NSURL)
    }
}
