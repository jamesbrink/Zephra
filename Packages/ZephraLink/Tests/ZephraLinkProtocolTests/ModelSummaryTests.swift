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
