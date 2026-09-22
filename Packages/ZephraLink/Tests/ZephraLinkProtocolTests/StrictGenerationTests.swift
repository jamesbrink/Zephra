import Foundation
import Testing
@testable import ZephraLinkProtocol

@Suite("Strict generation binds an immutable job independently of its transfer")
struct StrictGenerationTests {
    @Test("Retries with different transport blob IDs have the same digest")
    func transportIdentity() throws {
        var request = GenerationRequest(modelID: "model", count: 2, settings: LinkFixtures.settings)
        let input = GenerationInput(data: Data([1, 2, 3]))
        let first = StrictGeneration(request: request, input: input)
        request.referenceBlobID = UUID()
        #expect(try first.digest() == StrictGeneration(request: request, input: input).digest())
        #expect(try first.digest() != StrictGeneration(request: request,
            input: GenerationInput(data: Data([1, 2, 4]))).digest())
        var settings = request.settings
        settings.seed += 1
        request = GenerationRequest(modelID: request.modelID, count: request.count, settings: settings)
        #expect(try first.digest() != StrictGeneration(request: request, input: input).digest())
    }

    @Test("A one-picture strict generation digests exactly as it did before several were possible")
    func theGoldenDigestHasNotMoved() throws {
        let request = GenerationRequest(
            modelID: "model", count: 2, settings: LinkFixtures.settings,
            requestID: UUID(uuidString: "66666666-7777-8888-9999-000000000000")!)
        let job = StrictGeneration(request: request, input: GenerationInput(data: Data([1, 2, 3])))
        // Taken from the encoded form before `inputs` and `referenceBlobIDs` existed: neither
        // key is written for one picture, so neither moved it.
        #expect(
            try job.digest()
                == "9878083593f0937eb250c22122dfcccc03fbe5fd4c05b69a01c97311de8b5cae")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let json = String(decoding: try encoder.encode(job), as: UTF8.self)
        #expect(!json.contains("\"inputs\""), "and no new key was written to move it")
        #expect(!json.contains("referenceBlobIDs"))
        #expect(!json.contains("referenceImages"))
    }

    @Test("Three inputs digest independently of the blob ids that carried them")
    func severalInputsDigest() throws {
        var request = GenerationRequest(modelID: "model", count: 1, settings: LinkFixtures.settings)
        let inputs = [Data([1]), Data([2]), Data([3])].map { GenerationInput(data: $0) }
        let first = StrictGeneration(request: request, inputs: inputs)
        request.referenceBlobIDs = [UUID(), UUID(), UUID()]
        #expect(try first.digest() == StrictGeneration(request: request, inputs: inputs).digest())

        let reordered = StrictGeneration(request: request, inputs: inputs.reversed())
        #expect(try first.digest() != reordered.digest(), "the order is part of the work")
        #expect(try first.digest() != StrictGeneration(
            request: request, inputs: Array(inputs.prefix(2))).digest())
        #expect(try LinkFixtures.roundTrip(first).inputs == inputs)
    }

    @Test("Every opt-in command and reply survives encoding")
    func roundTrips() throws {
        let job = StrictGeneration(request: GenerationRequest(modelID: "model", count: 1,
            settings: LinkFixtures.settings))
        let commands: [MultiHostCommand] = [.offer(job), .submit(job), .receipt(UUID()), .previews(false),
            .cancelRun(UUID()), .listing(offset: 100, limit: 100, revision: "revision")]
        for command in commands {
            #expect(try LinkFixtures.roundTrip(Command.multiHost(command)) == .multiHost(command))
        }
        let listing = LibraryListing(revision: "revision", page: LibraryPage(entries: [LinkFixtures.entry], offset: 0, total: 1))
        #expect(try LinkFixtures.roundTrip(Reply.multiHost(.listing(listing))) == .multiHost(.listing(listing)))
    }
}
