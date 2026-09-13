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
