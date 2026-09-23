import AppKit
import Foundation
import ZephraCore
import ZephraEngine

/// Pictures drawn in-process so previews and the interface-only launch mode have something
/// to letterbox. Nothing here reaches the model or the network.
enum PreviewImages {
    /// A finished image record wrapping a drawn gradient, for previews of the done state.
    ///
    /// `frames` past 1 is what `GeneratedImage.isVideo` reads, for the `clip` screenshot build:
    /// there is no drawn MP4 behind it, only a poster, so the canvas shows the picture rather
    /// than `ClipPlayerView` — the same as a real clip before its file has landed.
    static func sample(
        size: ImageSize = ImageSize(width: 1024, height: 1024),
        prompt: String = "A lighthouse at dusk, fog rolling in over black rocks",
        reference: Data? = nil,
        frames: Int = 1,
        modelID: String = ModelCatalog.default.id
    ) -> GeneratedImage {
        GeneratedImage(
            pngData: gradientPNG(size: size),
            settings: GenerationSettings(
                prompt: prompt,
                size: size,
                steps: 9,
                guidance: 0,
                seed: 8_123_447_209_115_662,
                referenceImage: reference,
                frames: frames
            ),
            modelID: modelID,
            duration: .seconds(19) + .milliseconds(400)
        )
    }

    /// One press of Generate's worth of images, newest first as `history` holds them, all
    /// sharing a batch id so the strip under the capsule has a run to draw.
    static func run(
        of count: Int,
        prompt: String = "a red bicycle against a limestone wall, hard afternoon shadow"
    ) -> [GeneratedImage] {
        let batch = UUID()
        let size = ImageSize(width: 1024, height: 1024)
        let data = gradientPNG(size: size)
        let now = Date()
        return (0..<count).reversed().map { index in
            GeneratedImage(
                pngData: data,
                settings: GenerationSettings(
                    prompt: prompt,
                    size: size,
                    steps: 4,
                    guidance: 0,
                    seed: 8_123_447_209_115_662 &+ UInt64(index)
                ),
                modelID: ModelCatalog.default.id,
                createdAt: now.addingTimeInterval(-Double(count - index) * 7),
                duration: .seconds(6) + .milliseconds(900),
                batchID: batch
            )
        }
    }

    /// A small picture to sit in the reference well: the same gradient at a modest size.
    static func referencePNG() -> Data {
        gradientPNG(size: ImageSize(width: 512, height: 384))
    }

    /// `count` of them, each a different hue and a different shape, so a screenshot of the
    /// strip shows tiles that can be told apart and a reorder can be seen to have happened.
    static func referencePNGs(count: Int) -> [ReferencePicture] {
        (0..<max(0, count)).map { index in
            let size = index.isMultiple(of: 3)
                ? ImageSize(width: 512, height: 384)
                : (index.isMultiple(of: 2)
                    ? ImageSize(width: 384, height: 512)
                    : ImageSize(width: 448, height: 448))
            return ReferencePicture(
                data: gradientPNG(size: size, hue: Double(index) * 0.17),
                origin: "reference-\(index + 1).png",
                size: size)
        }
    }
}
