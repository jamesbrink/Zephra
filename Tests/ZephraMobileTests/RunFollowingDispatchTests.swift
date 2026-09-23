import Foundation
import Testing
import ZephraLinkClient
import ZephraLinkProtocol
@testable import ZephraMobile

@MainActor @Suite("A press's note moves with the Mac's run and clears when it ends")
struct RunFollowingDispatchTests {
    @Test func noteFollowsTheRun() async throws {
        let mac = MobileHostFixture(name: "Halcyon")
        let hosts = HostConnections(storage: nil,
            catalog: LibraryCatalog(libraryRoot: nil, filesRoot: nil), makeClient: { _ in mac.client })
        hosts.add(mac.preference, client: mac.client)
        let batch = UUID()
        mac.host.onCommand = { command in
            switch command {
            case .multiHost(.offer):
                mac.host.reply = .multiHost(.offer(HostOffer(refusal: nil, queueSeconds: 0,
                    preparationSeconds: 0, executionSeconds: 10, memoryMargin: 1000, modelLoaded: true,
                    queueCount: 0, queueRevision: "test", physicalMemory: 10000)))
            case .multiHost(.submit(let job)):
                mac.host.reply = .multiHost(.receipt(GenerationReceipt(requestID: job.request.requestID,
                    digest: try! job.digest(), batchID: batch, status: .accepted)))
            default: mac.host.reply = nil
            }
        }
        await mac.client.connect()
        try await MobileHostFixture.settle { mac.client.supportsMultiHost }
        let dispatch = GenerationDispatch(hosts: hosts, root: nil)
        let generation = StrictGeneration(request: GenerationRequest(modelID: "z-image-turbo-4bit",
            count: 1, settings: PromptDraft().settings))
        await dispatch.send(generation, references: [])
        #expect(dispatch.note == nil)
        #expect(dispatch.runNote == "Queued on Halcyon")

        let row = QueuedEntry(id: UUID(), batchID: batch, batchIndex: 0,
            modelID: generation.request.modelID, settings: generation.request.settings)
        func run(_ state: RunSummary.State) -> StateDelta {
            .today([RunSummary(id: batch, prompt: "", modelID: row.modelID, width: 8, height: 8,
                state: state, fileNames: [], seedCount: 1, startedAt: nil, finishedAt: nil)])
        }
        // In the order a Mac sends them: the queue empties before the run is named running,
        // and Today still holding the run as waiting is what bridges the two.
        try await mac.host.announce(StateDelta.queue([row]), kind: .delta)
        try await mac.host.announce(run(.waiting), kind: .delta)
        try await mac.host.announce(StateDelta.queue([]), kind: .delta)
        try await mac.host.announce(StateDelta.running(row), kind: .delta)
        try await mac.host.announce(StateDelta.engine(EngineStateDTO(kind: .generating,
            phase: "Denoising", isBusy: true)), kind: .delta)
        try await MobileHostFixture.settle { dispatch.runNote == "Denoising on Halcyon" }

        try await mac.host.announce(StateDelta.running(nil), kind: .delta)
        try await mac.host.announce(run(.finished), kind: .delta)
        try await mac.host.announce(StateDelta.engine(EngineStateDTO(kind: .ready,
            acceptsGeneration: true)), kind: .delta)
        try await MobileHostFixture.settle { dispatch.runNote == nil }
        #expect(dispatch.following == nil)
        await mac.stop()
        await hosts.catalog.removeHost(mac.preference.id)
    }
}
