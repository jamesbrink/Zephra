import Foundation
import Testing

@testable import ZephraCore

/// What a reference picture costs a run, which the scaled transient cannot say.
///
/// The rest of `transientBytes` is multiplicative over pixels and frames; this half is
/// additive, because a reference is fitted to the same megapixel budget whatever size is being
/// made, so its prefix cache is the same on a 768 picture as on a 2048 one.
@Suite("A reference picture's prefix cache is charged on top")
struct MemoryGuardScalingTests {
    static let guardian = MemoryGuard(budget: MemoryFitTests.sixteenDefault)

    /// A model whose references cost two gigabytes each, resident with a roomy peak so the
    /// scaled half of the answer is a round number to read the additive half off.
    static let prefixed = MemoryFitTests.model(
        peak: 20_000_000_000, tiled: 18_000_000_000, prefix: 2_000_000_000)

    /// One request at the descriptor's own default size, so the scaling is exactly one.
    static func settings(
        references: Int, guidance: Double = 0, negativePrompt: String? = nil
    ) -> GenerationSettings {
        let size = prefixed.capabilities.defaultSize
        return GenerationSettings(
            prompt: "a lighthouse", negativePrompt: negativePrompt, size: size, steps: 8,
            guidance: guidance, seed: 1,
            referenceImages: (0..<references).map {
                ReferencePicture(data: Data([UInt8($0)]), origin: nil)
            })
    }

    /// The transient with nothing in the well, which everything below is measured against.
    static var bare: Int64 {
        guardian.transientBytes(
            of: prefixed, residency: .resident, tile: nil, settings: settings(references: 0),
            runtime: .zero)
    }

    @Test("no picture in the well costs nothing, which is what every older entry does")
    func nothingIsChargedWithoutAPicture() {
        // The model that charges for pictures is charged nothing when it is handed none, and
        // the catalog's own entries are charged nothing whatever they are handed.
        #expect(Self.bare == Self.prefixed.peakBytes - Self.prefixed.residentBytes)
        for model in ModelCatalog.all where model.referencePrefixBytes == 0 {
            let size = model.capabilities.defaultSize
            let withPictures = GenerationSettings(
                prompt: "a lighthouse", size: size, steps: 8, guidance: 0, seed: 1,
                referenceImages: [ReferencePicture(data: Data([1]), origin: nil)],
                frames: model.capabilities.defaultFrames)
            var without = withPictures
            without.referenceImages = []
            #expect(
                Self.guardian.transientBytes(
                    of: model, residency: .resident, tile: nil, settings: withPictures,
                    runtime: .zero)
                    == Self.guardian.transientBytes(
                        of: model, residency: .resident, tile: nil, settings: without,
                        runtime: .zero),
                "\(model.id)")
        }
    }

    @Test("one picture adds its prefix cache once, and two add it twice")
    func picturesAreChargedOneByOne() {
        let one = Self.guardian.transientBytes(
            of: Self.prefixed, residency: .resident, tile: nil,
            settings: Self.settings(references: 1), runtime: .zero)
        let two = Self.guardian.transientBytes(
            of: Self.prefixed, residency: .resident, tile: nil,
            settings: Self.settings(references: 2), runtime: .zero)
        #expect(one == Self.bare + Self.prefixed.referencePrefixBytes)
        #expect(two == Self.bare + 2 * Self.prefixed.referencePrefixBytes)
    }

    @Test("classifier-free guidance doubles the cache, since the second forward keeps its own")
    func guidanceDoublesTheCache() {
        let guided = Self.guardian.transientBytes(
            of: Self.prefixed, residency: .resident, tile: nil,
            settings: Self.settings(references: 1, guidance: 4, negativePrompt: "blurry"),
            runtime: .zero)
        #expect(guided == Self.bare + 2 * Self.prefixed.referencePrefixBytes)
        // Guidance with no negative prompt runs one forward, and so does a negative prompt at
        // guidance one: a backend runs the second pass on exactly both together.
        for settings in [
            Self.settings(references: 1, guidance: 4),
            Self.settings(references: 1, guidance: 4, negativePrompt: ""),
            Self.settings(references: 1, guidance: 1, negativePrompt: "blurry"),
        ] {
            #expect(
                Self.guardian.transientBytes(
                    of: Self.prefixed, residency: .resident, tile: nil, settings: settings,
                    runtime: .zero) == Self.bare + Self.prefixed.referencePrefixBytes)
        }
    }

    @Test("the picture's cost does not follow the size, and the rest of the run does")
    func theCacheIsAdditiveRatherThanScaled() {
        var large = Self.settings(references: 1)
        let size = Self.prefixed.capabilities.defaultSize
        large.size = ImageSize(width: size.width * 2, height: size.height)
        let charged = Self.guardian.transientBytes(
            of: Self.prefixed, residency: .resident, tile: nil, settings: large, runtime: .zero)
        // Twice the pixels is twice the transient, plus the one picture's cache unchanged.
        #expect(charged == 2 * Self.bare + Self.prefixed.referencePrefixBytes)
    }
}
