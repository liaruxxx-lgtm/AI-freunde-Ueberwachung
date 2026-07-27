import AVFoundation
import CoreImage
import Foundation
import ImageIO
import Vision

struct MediaAnalysisResult: Sendable {
    let labels: [String]
    let suggestedClothingTags: [String]
}

enum LocalMediaAnalyzerError: LocalizedError, Equatable {
    case unreadableMedia

    var errorDescription: String? {
        switch self {
        case .unreadableMedia:
            "Die Mediendatei fehlt oder konnte nicht gelesen werden."
        }
    }
}

enum LocalMediaAnalyzer {
    static func analyze(
        url: URL,
        kind: MediaKind
    ) async throws -> MediaAnalysisResult {
        let images: [CGImage]
        switch kind {
        case .image:
            images = imageFrames(from: url)
        case .video:
            images = try await videoFrames(from: url)
        }

        guard !images.isEmpty else {
            throw LocalMediaAnalyzerError.unreadableMedia
        }

        var scoredLabels: [String: Float] = [:]
        var clothing = Set<String>()
        for image in images {
            let classifications = classify(image)
            for classification in classifications {
                scoredLabels[classification.identifier] = max(
                    scoredLabels[classification.identifier] ?? 0,
                    classification.confidence
                )
                clothing.formUnion(clothingTags(for: classification.identifier))
            }
        }

        let labels = scoredLabels
            .sorted { lhs, rhs in
                lhs.value == rhs.value ? lhs.key < rhs.key : lhs.value > rhs.value
            }
            .prefix(10)
            .map { $0.key }

        return MediaAnalysisResult(
            labels: labels,
            suggestedClothingTags: clothing.sorted()
        )
    }

    private static func imageFrames(from url: URL) -> [CGImage] {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(
                source,
                0,
                [kCGImageSourceShouldCacheImmediately: true] as CFDictionary
              ) else {
            return []
        }
        return [image]
    }

    private static func videoFrames(from url: URL) async throws -> [CGImage] {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration)
        let seconds = max(0, CMTimeGetSeconds(duration))
        let times = [0.1, seconds * 0.5, max(0.1, seconds - 0.25)]
            .map { CMTime(seconds: $0, preferredTimescale: 600) }

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 1400, height: 1400)

        var frames: [CGImage] = []
        for time in times {
            if let image = try? await generator.image(at: time).image {
                frames.append(image)
            }
        }
        return frames
    }

    private static func classify(_ image: CGImage) -> [VNClassificationObservation] {
        let request = VNClassifyImageRequest()
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([request])
            return (request.results ?? [])
                .filter { $0.confidence >= 0.16 }
                .prefix(18)
                .map { $0 }
        } catch {
            return []
        }
    }

    private static func clothingTags(for identifier: String) -> Set<String> {
        let value = identifier.lowercased()
        let mappings: [(needles: [String], tag: String)] = [
            (["jacket", "windbreaker"], "Jacke"),
            (["coat", "overcoat", "parka"], "Mantel"),
            (["hoodie", "sweatshirt"], "Hoodie"),
            (["sweater", "pullover", "cardigan"], "Pullover"),
            (["t-shirt", "tee shirt"], "T-Shirt"),
            (["shirt", "blouse", "top"], "Oberteil"),
            (["dress", "gown"], "Kleid"),
            (["skirt"], "Rock"),
            (["jeans", "denim"], "Jeans"),
            (["pants", "trousers", "slacks"], "Hose"),
            (["suit", "formal wear", "tuxedo"], "Anzug"),
            (["hat", "cap", "beanie"], "Kopfbedeckung"),
            (["sneaker", "shoe", "boot", "footwear"], "Schuhe"),
            (["scarf"], "Schal")
        ]

        return Set(
            mappings.compactMap { mapping in
                mapping.needles.contains(where: value.contains) ? mapping.tag : nil
            }
        )
    }
}

@MainActor
extension LibraryStore {
    func analyzeMediaItem(id: UUID) async throws {
        guard let item = mediaItem(id: id) else {
            throw LibraryStoreError.mediaNotFound(id)
        }
        let result = try await LocalMediaAnalyzer.analyze(
            url: try validatedMediaURL(for: item),
            kind: item.kind
        )
        guard var latestItem = mediaItem(id: id) else {
            throw LibraryStoreError.mediaNotFound(id)
        }
        let suggestions = result.suggestedClothingTags.map { "Kleidungsvorschlag: \($0)" }
        latestItem.analysisLabels = Array(Set(result.labels + suggestions)).sorted()
        try updateMedia(latestItem)
    }

}
