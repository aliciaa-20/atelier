import AppKit
import SwiftUI

/// Extracts an average color from the current track's artwork, for the
/// waveform's `.gradient` per the "match the album artwork" request —
/// adapted from boring.notch's `avgColor`/`coloredSpectrogram` idea, done
/// here as a small `CIAreaAverage` render rather than their approach.
///
/// Fetches through `ArtworkImageCache` (shared with `ArtworkView`) rather
/// than its own `URLSession` call — two independent fetches of the same
/// URL were racing each other and were the real cause of artwork taking
/// ~1.5s to appear.
@MainActor
final class ArtworkColorLoader: ObservableObject {
    @Published private(set) var color: Color = .white

    private var loadedURL: URL?
    private let context = CIContext()

    func load(from url: URL?) {
        guard url != loadedURL else { return }
        loadedURL = url

        guard let url else {
            color = .white
            return
        }

        Task {
            guard let data = await ArtworkImageCache.shared.data(for: url),
                  let nsImage = NSImage(data: data),
                  let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }

            let ciImage = CIImage(cgImage: cgImage)
            guard let filter = CIFilter(name: "CIAreaAverage", parameters: [
                kCIInputImageKey: ciImage,
                kCIInputExtentKey: CIVector(cgRect: ciImage.extent),
            ]), let outputImage = filter.outputImage else { return }

            var bitmap = [UInt8](repeating: 0, count: 4)
            context.render(
                outputImage,
                toBitmap: &bitmap,
                rowBytes: 4,
                bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                format: .RGBA8,
                colorSpace: nil
            )

            // Stale response from a since-superseded track change — drop it.
            guard self.loadedURL == url else { return }
            self.color = Color(
                red: Double(bitmap[0]) / 255,
                green: Double(bitmap[1]) / 255,
                blue: Double(bitmap[2]) / 255
            )
        }
    }
}
