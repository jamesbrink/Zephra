import Foundation
import Testing
import ZephraCore
@testable import ZephraLinkProtocol

@Suite("A model crosses with everything a form needs to draw itself")
struct ModelSummaryTests {
    @Test("Every catalog entry summarises and comes back the same")
    func catalogRoundTrips() throws {
        for descriptor in ModelCatalog.all {
            let summary = ModelSummary(descriptor)
            #expect(try LinkFixtures.roundTrip(summary) == summary)
            #expect(summary.id == descriptor.id)
            #expect(summary.familyID == descriptor.backend.rawValue)
        }
    }

    @Test("Capabilities rebuild into the real type, so clamp is the same code on both ends")
    func capabilitiesRebuild() throws {
        for descriptor in ModelCatalog.all {
            let summary = CapabilitiesSummary(descriptor.capabilities)
            #expect(try LinkFixtures.roundTrip(summary).capabilities == descriptor.capabilities)
        }
    }

    @Test("A clip model keeps its frame ladder, its rate and whether it makes sound")
    func videoFactsSurvive() throws {
        let clips = ModelCatalog.all.filter(\.capabilities.producesVideo)
        #expect(!clips.isEmpty, "the catalog has no video model to check")
        for descriptor in clips {
            let read = try LinkFixtures.roundTrip(CapabilitiesSummary(descriptor.capabilities))
            #expect(read.frameBounds == descriptor.capabilities.frameBounds)
            #expect(read.frameAlignment == descriptor.capabilities.frameAlignment)
            #expect(read.frameRate == descriptor.capabilities.frameRate)
            #expect(read.continuationFrames == descriptor.capabilities.continuationFrames)
            #expect(read.producesAudio == descriptor.capabilities.producesAudio)
        }
    }

    @Test("A model written by a Mac from before the memory gate reads as one that can be chosen")
    func olderMacsAreReadAsSelectable() throws {
        let capabilities = String(
            decoding: try LinkJSON.encode(CapabilitiesSummary(LinkFixtures.capabilities)),
            as: UTF8.self)
        let json = #"""
            {"capabilities":\#(capabilities),"displayName":"Z-Image Turbo",\#
            "familyID":"z-image","id":"z-image-turbo-4bit","variantName":"4-bit"}
            """#

        let summary = try LinkJSON.decode(ModelSummary.self, from: Data(json.utf8))

        #expect(summary.isSelectable, "absence was never a refusal")
        #expect(summary.memoryNote == nil)
        #expect(summary == LinkFixtures.model, "and the rest reads as it always did")
    }

    @Test("A model this Mac cannot hold crosses greyed, with the words that say why")
    func theMemoryVerdictCrosses() throws {
        let budget = MemoryBudget(physicalMemory: 16 << 30, gpuWorkingSet: 11_000_000_000)
        let tight = ModelCatalog.ltx2DistilledAudio4bit
        let fit = ModelCatalog.fit(tight, budget: budget)
        #expect(!fit.isSelectable, "the fixture budget must be one this model is over")

        let summary = ModelSummary(tight, fit: fit)
        let read = try LinkFixtures.roundTrip(summary)

        #expect(read == summary)
        #expect(!read.isSelectable)
        #expect(read.memoryNote == fit.label)
    }

    @Test("A model the Mac runs crosses as one that can be chosen")
    func aFittingModelCrossesSelectable() throws {
        let budget = MemoryBudget(physicalMemory: 128_000_000_000, gpuWorkingSet: 100_000_000_000)
        let model = ModelCatalog.default
        let read = try LinkFixtures.roundTrip(
            ModelSummary(model, fit: ModelCatalog.fit(model, budget: budget)))

        #expect(read.isSelectable)
        #expect(read.memoryNote == nil, "nothing worth saying about a model that just fits")
    }

    @Test("The label puts the variant beside the name")
    func labelReadsAsOneLine() {
        #expect(LinkFixtures.model.label == "Z-Image Turbo (4-bit)")
    }

    @Test("Every availability answer crosses with the words the Mac would show")
    func availabilityRoundTrips() throws {
        let answers: [ModelAvailability] = [
            .available, .needsDownload(bytes: 4_000), .needsDownloadAndBuild(bytes: 9_000),
            .needsBuild, .missing(reason: "Nothing to build it from."),
        ]
        #expect(answers.count == AvailabilityDTO.Kind.allCases.count)
        for answer in answers {
            let dto = AvailabilityDTO(answer)
            #expect(try LinkFixtures.roundTrip(dto) == dto)
            #expect(dto.label == answer.label)
            #expect(dto.reason == answer.reason)
            #expect(dto.needsNetwork == answer.needsNetwork)
        }
    }
}
