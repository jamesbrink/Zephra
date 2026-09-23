import Foundation
import Testing
import ZephraLinkClient
import ZephraLinkProtocol

@testable import ZephraMobile

/// A strip crossing the link: what the offer names, what the blobs are, and what the durable
/// record keeps.
///
/// The order is the whole of it. The model reads the pictures in the order they were chosen, so
/// the blobs go in that order and the inputs that name them are in that order too — a receipt
/// digests the inputs, so a set that arrived shuffled would be a different work.
@MainActor
@Suite("An offer and a submission carry every picture")
struct ReferenceStripDispatchTests {
    @Test("Three pictures are offered, sent and recorded as three, in order")
    func severalPicturesCrossInOrder() async throws {
        let mac = MobileHostFixture(name: "A")
        let hosts = HostConnections(
            storage: nil, catalog: LibraryCatalog(libraryRoot: nil, filesRoot: nil),
            makeClient: { _ in mac.client })
        hosts.add(mac.preference, client: mac.client)
        var offered: [StrictGeneration] = []
        mac.host.onCommand = { command in
            switch command {
            case .multiHost(.offer(let job)):
                offered.append(job)
                mac.host.reply = .multiHost(.offer(HostOffer(
                    refusal: nil, queueSeconds: 0, preparationSeconds: 0, executionSeconds: 30,
                    memoryMargin: 1000, modelLoaded: true, queueCount: 0, queueRevision: "test",
                    physicalMemory: 10000)))
            case .multiHost(.submit(let job)):
                mac.host.reply = .multiHost(.receipt(GenerationReceipt(
                    requestID: job.request.requestID, digest: try! job.digest(),
                    batchID: UUID(), status: .accepted)))
            default: mac.host.reply = nil
            }
        }
        await mac.client.connect()
        try await MobileHostFixture.settle { mac.client.supportsMultiHost }

        let dispatch = GenerationDispatch(hosts: hosts, root: nil)
        dispatch.destination = mac.preference.id
        let pictures = [
            Data(repeating: 1, count: 16), Data(repeating: 2, count: 24),
            Data(repeating: 3, count: 32),
        ]
        let generation = StrictGeneration(
            request: GenerationRequest(
                modelID: "z-image-turbo-4bit", count: 1, settings: PromptDraft().settings),
            inputs: pictures.map { GenerationInput(data: $0) })
        await dispatch.send(generation, references: pictures)

        #expect(mac.host.blobs == pictures, "in the order the model reads them")
        #expect(offered.first?.inputs.count == 3, "the offer is about all three")
        let submitted = mac.host.commands.compactMap { command -> StrictGeneration? in
            if case .multiHost(.submit(let job)) = command { return job }
            return nil
        }
        #expect(submitted.first?.inputs.count == 3)
        #expect(submitted.first?.request.referenceBlobIDs.count == 3)
        #expect(dispatch.submissions.first?.state == .accepted)
        #expect(
            dispatch.submissions.first?.generation.inputs.count == 3,
            "and the record kept for reconciling names all three")
        await mac.stop()
    }
}
