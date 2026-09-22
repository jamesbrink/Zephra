import Foundation
import Testing

@testable import ZephraCore

/// What a request's pictures become on the way to a model that may read fewer of them.
@Suite("Trimming a strip of reference pictures to what a model reads")
struct ReferenceClampTests {
    private static func picture(_ byte: UInt8, bytes: Int = 4) -> ReferencePicture {
        ReferencePicture(data: Data(repeating: byte, count: bytes), origin: "\(byte).png")
    }

    private static func capabilities(
        reads: Bool = true, count: ClosedRange<Int> = 1...1
    ) -> ModelCapabilities {
        ModelCapabilities(
            sizeAlignment: 16, sizePresets: [ImageSize(width: 64, height: 64)],
            sizeBounds: 64...1024, defaultSize: ImageSize(width: 64, height: 64),
            stepBounds: 4...4, defaultSteps: 4, guidanceBounds: 0...0, defaultGuidance: 0,
            supportsNegativePrompt: false, supportsSeed: true,
            supportsReferenceImage: reads, referenceImageCount: count)
    }

    private static func settings(_ pictures: [ReferencePicture]) -> GenerationSettings {
        var settings = GenerationSettings(
            prompt: "a lighthouse", size: ImageSize(width: 64, height: 64), steps: 4,
            guidance: 0, seed: 1)
        settings.referenceImages = pictures
        return settings
    }

    @Test("a one-picture model keeps the first and drops the rest")
    func trimsToOne() {
        let clamped = Self.capabilities().clamp(
            Self.settings([Self.picture(1), Self.picture(2), Self.picture(3)]))
        #expect(clamped.referenceImages.count == 1)
        #expect(clamped.referenceOrigin == "1.png", "the one chosen first survives")
    }

    @Test("a model that reads ten keeps three in the order they were chosen")
    func keepsSeveral() {
        let clamped = Self.capabilities(count: 1...10).clamp(
            Self.settings([Self.picture(1), Self.picture(2), Self.picture(3)]))
        #expect(clamped.referenceImages.map(\.origin) == ["1.png", "2.png", "3.png"])
    }

    @Test("a model that reads none is clamped free of every picture and every origin")
    func dropsThemAll() {
        let clamped = Self.capabilities(reads: false, count: 1...10).clamp(
            Self.settings([Self.picture(1), Self.picture(2)]))
        #expect(clamped.referenceImages.isEmpty)
        #expect(clamped.referenceImage == nil)
        #expect(clamped.referenceOrigin == nil)
    }

    @Test("the byte budget drops from the end, whatever the model would read")
    func budgetTrims() {
        let heavy = ReferencePicture(
            data: Data(repeating: 0x2A, count: ReferenceLimits.maximumTotalBytes / 2 + 1))
        let clamped = Self.capabilities(count: 1...10).clamp(Self.settings([heavy, heavy, heavy]))
        #expect(clamped.referenceImages.count == 1)
    }

    @Test("never more than the link and the record can carry, whatever a model claims")
    func theHardLimitWins() {
        let strip = (0..<20).map { Self.picture(UInt8($0)) }
        let clamped = Self.capabilities(count: 1...50).clamp(Self.settings(strip))
        #expect(clamped.referenceImages.count == ReferenceLimits.maximumPictures)
    }

    @Test("a picture whose bytes were stripped for the wire is not one a model can read")
    func strippedPicturesAreDropped() {
        let stripped = Self.picture(1).withoutPixels()
        let clamped = Self.capabilities(count: 1...10).clamp(
            Self.settings([stripped, Self.picture(2)]))
        #expect(clamped.referenceImages.map(\.origin) == ["2.png"])
    }

    @Test("a model reads several only when it reads any")
    func theDerivedFlag() {
        #expect(!Self.capabilities().acceptsSeveralReferences)
        #expect(Self.capabilities(count: 1...10).acceptsSeveralReferences)
        #expect(!Self.capabilities(reads: false, count: 1...10).acceptsSeveralReferences)
    }
}
