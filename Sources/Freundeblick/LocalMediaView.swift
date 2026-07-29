import AVFoundation
import AppKit
import SwiftUI

struct LocalMediaView: View {
    @EnvironmentObject private var store: LibraryStore
    @AppStorage("allowMediaPreviews") private var allowMediaPreviews = true

    let media: MediaItem?
    var cornerRadius: CGFloat = 18

    @State private var image: NSImage?
    @State private var previewUnavailable = false

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [AppTheme.berry.opacity(0.23), AppTheme.apricot.opacity(0.34)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                if let image, allowMediaPreviews {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(
                            width: geometry.size.width,
                            height: geometry.size.height
                        )
                        .clipped()
                } else {
                    Image(systemName: placeholderSymbol)
                        .font(.system(size: 38, weight: .medium))
                        .foregroundStyle(.white.opacity(0.9))
                        .symbolRenderingMode(.hierarchical)
                }

                if previewUnavailable {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(7)
                        .background(AppTheme.coral, in: Circle())
                        .padding(8)
                        .frame(
                            maxWidth: .infinity,
                            maxHeight: .infinity,
                            alignment: .bottomTrailing
                        )
                        .help("Die Mediendatei fehlt oder kann nicht geöffnet werden.")
                }
            }
            .frame(
                width: geometry.size.width,
                height: geometry.size.height
            )
            .clipShape(
                RoundedRectangle(
                    cornerRadius: cornerRadius,
                    style: .continuous
                )
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: previewTaskID) {
            image = nil
            previewUnavailable = false
            guard allowMediaPreviews else { return }
            let loadedImage = await loadImage()
            image = loadedImage
            previewUnavailable = media != nil && loadedImage == nil
        }
        .accessibilityLabel(accessibilityDescription)
    }

    private func loadImage() async -> NSImage? {
        guard let media else { return nil }
        let url = store.mediaURL(for: media)

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

    private var placeholderSymbol: String {
        if !allowMediaPreviews, media != nil {
            return "eye.slash.fill"
        }
        if previewUnavailable {
            return "photo.badge.exclamationmark"
        }
        return media?.kind == .video
            ? "video.fill"
            : "person.crop.circle.fill"
    }

    private var accessibilityDescription: String {
        guard let media else {
            return "Kein Profilbild"
        }
        if !allowMediaPreviews {
            return "\(media.originalFilename), Vorschau ausgeblendet"
        }
        if previewUnavailable {
            return "\(media.originalFilename), Vorschau nicht verfügbar"
        }
        return media.originalFilename
    }

    private var previewTaskID: String {
        guard let media else {
            return "none-\(allowMediaPreviews)"
        }
        let url = store.mediaURL(for: media)
        let values = try? url.resourceValues(
            forKeys: [.contentModificationDateKey, .fileSizeKey]
        )
        let modification = values?.contentModificationDate?
            .timeIntervalSinceReferenceDate ?? -1
        let fileSize = values?.fileSize ?? -1
        return "\(media.id.uuidString)-\(allowMediaPreviews)-"
            + "\(media.originalFilename)-\(modification)-\(fileSize)"
    }
}
