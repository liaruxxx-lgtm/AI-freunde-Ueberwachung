import AVFoundation
import AppKit
import SwiftUI

struct LocalMediaView: View {
    let media: MediaItem?
    var cornerRadius: CGFloat = 18

    @State private var image: NSImage?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [AppTheme.berry.opacity(0.23), AppTheme.apricot.opacity(0.34)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: media?.kind == .video ? "video.fill" : "person.crop.circle.fill")
                    .font(.system(size: 38, weight: .medium))
                    .foregroundStyle(.white.opacity(0.9))
                    .symbolRenderingMode(.hierarchical)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .task(id: media?.id) {
            image = await loadImage()
        }
    }

    private func loadImage() async -> NSImage? {
        guard let media else { return nil }
        let url = LibraryPaths.mediaDirectory.appendingPathComponent(media.storedFilename)

        if media.kind == .image {
            return NSImage(contentsOf: url)
        }

        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        do {
            let cgImage = try await generator.image(at: .zero).image
            return NSImage(cgImage: cgImage, size: .zero)
        } catch {
            return nil
        }
    }
}
