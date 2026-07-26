import AppKit
import SwiftUI

enum ProfileImageCropError: LocalizedError {
    case unreadableImage
    case renderingFailed

    var errorDescription: String? {
        switch self {
        case .unreadableImage:
            "Das ausgewählte Bild konnte nicht gelesen werden."
        case .renderingFailed:
            "Der Profilbild-Zuschnitt konnte nicht erstellt werden."
        }
    }
}

enum ProfileImageCropGeometry {
    static func constrainedOffset(
        imageSize: CGSize,
        viewportSide: CGFloat,
        zoom: CGFloat,
        offset: CGSize
    ) -> CGSize {
        guard imageSize.width > 0,
              imageSize.height > 0,
              viewportSide > 0
        else {
            return .zero
        }

        let safeZoom = min(max(zoom, 1), 4)
        let baseScale = max(
            viewportSide / imageSize.width,
            viewportSide / imageSize.height
        )
        let displayedWidth = imageSize.width * baseScale * safeZoom
        let displayedHeight = imageSize.height * baseScale * safeZoom
        let maximumX = max(0, (displayedWidth - viewportSide) / 2)
        let maximumY = max(0, (displayedHeight - viewportSide) / 2)

        return CGSize(
            width: min(max(offset.width, -maximumX), maximumX),
            height: min(max(offset.height, -maximumY), maximumY)
        )
    }

    static func sourceRect(
        imageSize: CGSize,
        viewportSide: CGFloat,
        zoom: CGFloat,
        offset: CGSize
    ) -> CGRect {
        guard imageSize.width > 0,
              imageSize.height > 0,
              viewportSide > 0
        else {
            return .zero
        }

        let safeZoom = min(max(zoom, 1), 4)
        let baseScale = max(
            viewportSide / imageSize.width,
            viewportSide / imageSize.height
        )
        let displayScale = baseScale * safeZoom
        let displayedWidth = imageSize.width * displayScale
        let displayedHeight = imageSize.height * displayScale
        let safeOffset = constrainedOffset(
            imageSize: imageSize,
            viewportSide: viewportSide,
            zoom: safeZoom,
            offset: offset
        )
        let sourceSide = viewportSide / displayScale
        let sourceX = (
            (displayedWidth - viewportSide) / 2 - safeOffset.width
        ) / displayScale
        let sourceTop = (
            (displayedHeight - viewportSide) / 2 - safeOffset.height
        ) / displayScale
        let sourceY = imageSize.height - sourceTop - sourceSide

        return CGRect(
            x: min(max(sourceX, 0), max(0, imageSize.width - sourceSide)),
            y: min(max(sourceY, 0), max(0, imageSize.height - sourceSide)),
            width: sourceSide,
            height: sourceSide
        )
    }
}

enum ProfileImageCropRenderer {
    static func pngData(
        from image: NSImage,
        viewportSide: CGFloat,
        zoom: CGFloat,
        offset: CGSize,
        outputPixels: Int = 1_024
    ) throws -> Data {
        guard image.size.width > 0, image.size.height > 0 else {
            throw ProfileImageCropError.unreadableImage
        }
        let sourceRect = ProfileImageCropGeometry.sourceRect(
            imageSize: image.size,
            viewportSide: viewportSide,
            zoom: zoom,
            offset: offset
        )
        guard sourceRect.width > 0,
              let bitmap = NSBitmapImageRep(
                  bitmapDataPlanes: nil,
                  pixelsWide: outputPixels,
                  pixelsHigh: outputPixels,
                  bitsPerSample: 8,
                  samplesPerPixel: 4,
                  hasAlpha: true,
                  isPlanar: false,
                  colorSpaceName: .deviceRGB,
                  bitmapFormat: [],
                  bytesPerRow: 0,
                  bitsPerPixel: 0
              ),
              let graphicsContext = NSGraphicsContext(bitmapImageRep: bitmap)
        else {
            throw ProfileImageCropError.renderingFailed
        }

        bitmap.size = NSSize(width: outputPixels, height: outputPixels)
        let outputRect = NSRect(
            x: 0,
            y: 0,
            width: outputPixels,
            height: outputPixels
        )

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphicsContext
        graphicsContext.imageInterpolation = .high
        NSColor.clear.setFill()
        outputRect.fill()
        image.draw(
            in: outputRect,
            from: sourceRect,
            operation: .copy,
            fraction: 1
        )
        NSGraphicsContext.restoreGraphicsState()

        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            throw ProfileImageCropError.renderingFailed
        }
        return data
    }
}

struct ProfileImageCropEditorView: View {
    @Environment(\.dismiss) private var dismiss

    let image: NSImage
    let sourceFilename: String
    let onSave: (Data) throws -> Void

    @State private var zoom: CGFloat = 1
    @State private var offset: CGSize = .zero
    @GestureState private var dragTranslation: CGSize = .zero
    @State private var errorMessage: String?

    private let viewportSide: CGFloat = 410

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Profilbild zuschneiden")
                        .font(.title2.weight(.bold))
                    Text(sourceFilename)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Button("Abbrechen") { dismiss() }
                Button("Zuschneiden & verwenden", action: save)
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.berry)
            }
            .padding(20)

            Divider()

            VStack(spacing: 18) {
                cropPreview

                HStack(spacing: 12) {
                    Image(systemName: "photo")
                        .foregroundStyle(.secondary)
                    Slider(value: $zoom, in: 1...4)
                        .onChange(of: zoom) { _, newZoom in
                            offset = constrained(offset, zoom: newZoom)
                        }
                    Image(systemName: "photo.fill")
                        .foregroundStyle(AppTheme.berry)
                    Text("\(Int((zoom * 100).rounded())) %")
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .frame(width: 54, alignment: .trailing)
                    Button("Zurücksetzen") {
                        withAnimation {
                            zoom = 1
                            offset = .zero
                        }
                    }
                }

                Label(
                    "Ziehe das Bild mit der Maus und stelle die Größe mit dem Regler ein. Der sichtbare quadratische Ausschnitt wird als neue lokale Kopie gespeichert.",
                    systemImage: "hand.draw.fill"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: viewportSide, alignment: .leading)
            }
            .padding(22)
        }
        .frame(width: 650, height: 650)
        .alert("Zuschneiden nicht möglich", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var cropPreview: some View {
        let displayOffset = constrained(
            CGSize(
                width: offset.width + dragTranslation.width,
                height: offset.height + dragTranslation.height
            ),
            zoom: zoom
        )

        return ZStack {
            Color.black.opacity(0.9)
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: viewportSide, height: viewportSide)
                .scaleEffect(zoom)
                .offset(
                    x: displayOffset.width,
                    y: displayOffset.height
                )

            CropGuideGrid()
                .stroke(.white.opacity(0.48), lineWidth: 1)

            RoundedRectangle(cornerRadius: 38, style: .continuous)
                .stroke(.white, lineWidth: 3)
        }
        .frame(width: viewportSide, height: viewportSide)
        .clipShape(RoundedRectangle(cornerRadius: 38, style: .continuous))
        .shadow(color: .black.opacity(0.22), radius: 18, y: 8)
        .contentShape(Rectangle())
        .gesture(
            DragGesture()
                .updating($dragTranslation) { value, state, _ in
                    state = value.translation
                }
                .onEnded { value in
                    offset = constrained(
                        CGSize(
                            width: offset.width + value.translation.width,
                            height: offset.height + value.translation.height
                        ),
                        zoom: zoom
                    )
                }
        )
        .accessibilityLabel("Vorschau des Profilbild-Zuschnitts")
        .accessibilityHint("Bild ziehen oder Zoom-Regler verwenden")
    }

    private func constrained(_ value: CGSize, zoom: CGFloat) -> CGSize {
        ProfileImageCropGeometry.constrainedOffset(
            imageSize: image.size,
            viewportSide: viewportSide,
            zoom: zoom,
            offset: value
        )
    }

    private func save() {
        do {
            let safeOffset = constrained(offset, zoom: zoom)
            let data = try ProfileImageCropRenderer.pngData(
                from: image,
                viewportSide: viewportSide,
                zoom: zoom,
                offset: safeOffset
            )
            try onSave(data)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct CropGuideGrid: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        for fraction in [CGFloat(1) / 3, CGFloat(2) / 3] {
            let x = rect.minX + rect.width * fraction
            path.move(to: CGPoint(x: x, y: rect.minY))
            path.addLine(to: CGPoint(x: x, y: rect.maxY))

            let y = rect.minY + rect.height * fraction
            path.move(to: CGPoint(x: rect.minX, y: y))
            path.addLine(to: CGPoint(x: rect.maxX, y: y))
        }
        return path
    }
}
