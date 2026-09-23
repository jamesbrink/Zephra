import Foundation
import Testing
import ZephraCore

@testable import ZephraLinkProtocol

/// How many pictures a model reads is a fact about that model, so it crosses inside its
/// capabilities rather than as a flag about the Mac.
@Suite("A model says how many pictures it reads, and silence says one")
struct CapabilitiesSummaryTests {
    private static func reading(_ count: ClosedRange<Int>) -> ModelCapabilities {
        let base = LinkFixtures.capabilities
        return ModelCapabilities(
            sizeAlignment: base.sizeAlignment, sizePresets: base.sizePresets,
            sizeBounds: base.sizeBounds, defaultSize: base.defaultSize,
            stepBounds: base.stepBounds, defaultSteps: base.defaultSteps,
            guidanceBounds: base.guidanceBounds, defaultGuidance: base.defaultGuidance,
            supportsNegativePrompt: base.supportsNegativePrompt, supportsSeed: base.supportsSeed,
            supportsReferenceImage: true, referenceImageCount: count,
            referenceStrengthBounds: 1...1, defaultReferenceStrength: 1)
    }

    @Test("a count past one crosses and rebuilds into the real capabilities")
    func severalCross() throws {
        let capabilities = Self.reading(1...10)
        let read = try LinkFixtures.roundTrip(CapabilitiesSummary(capabilities))
        #expect(read.referenceImageCount == 1...10)
        #expect(read.capabilities == capabilities)
        #expect(read.capabilities.acceptsSeveralReferences)
    }

    @Test("a one-picture model says nothing, so its summary is the bytes it always was")
    func oneIsSilent() throws {
        let json = String(
            decoding: try LinkJSON.encode(CapabilitiesSummary(LinkFixtures.capabilities)),
            as: UTF8.self)
        #expect(!json.contains("referenceImageCount"))
    }

    @Test("a Mac from before the field reads as a Mac that reads one picture")
    func olderMacsReadAsOne() throws {
        let json = String(
            decoding: try LinkJSON.encode(CapabilitiesSummary(Self.reading(1...10))), as: UTF8.self)
        let older = json.replacingOccurrences(
            of: "\"referenceImageCount\":[1,10],", with: "")
        #expect(older != json, "the field was there to remove")

        let read = try LinkJSON.decode(CapabilitiesSummary.self, from: Data(older.utf8))
        #expect(read.referenceImageCount == 1...1)
        #expect(!read.capabilities.acceptsSeveralReferences)
    }

    @Test("a model that reads alpha says so, and silence means the picture is matted over white")
    func alphaCrossesAndSilenceMeansWhite() throws {
        // The phone draws `ReferenceMatteNote` from this, so a Mac whose model keeps a cut-out
        // and a Mac from before any model did must not read the same.
        let base = Self.reading(1...10)
        let reads = ModelCapabilities(
            sizeAlignment: base.sizeAlignment, sizePresets: base.sizePresets,
            sizeBounds: base.sizeBounds, defaultSize: base.defaultSize,
            stepBounds: base.stepBounds, defaultSteps: base.defaultSteps,
            guidanceBounds: base.guidanceBounds, defaultGuidance: base.defaultGuidance,
            supportsNegativePrompt: base.supportsNegativePrompt, supportsSeed: base.supportsSeed,
            supportsReferenceImage: true, referenceImageCount: base.referenceImageCount,
            readsTransparentReferences: true,
            referenceStrengthBounds: 1...1, defaultReferenceStrength: 1)
        let read = try LinkFixtures.roundTrip(CapabilitiesSummary(reads))
        #expect(read.readsTransparentReferences)
        #expect(read.capabilities == reads)
        // A model that mattes says nothing, so its summary is the bytes it always was.
        let quiet = String(
            decoding: try LinkJSON.encode(CapabilitiesSummary(base)), as: UTF8.self)
        #expect(!quiet.contains("readsTransparentReferences"))
        // And a Mac from before the field is read as one that matted.
        let json = String(decoding: try LinkJSON.encode(CapabilitiesSummary(reads)), as: UTF8.self)
        let older = json.replacingOccurrences(
            of: "\"readsTransparentReferences\":true,", with: "")
        #expect(older != json, "the field was there to remove")
        #expect(
            try !LinkJSON.decode(CapabilitiesSummary.self, from: Data(older.utf8))
                .readsTransparentReferences)
    }
}
