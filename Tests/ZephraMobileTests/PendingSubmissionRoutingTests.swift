import Foundation
import Testing
import ZephraLinkClient
import ZephraLinkProtocol
@testable import ZephraMobile

@MainActor @Suite("Unpublished accepted jobs reserve capacity without double counting")
struct PendingSubmissionRoutingTests {
    @Test func acceptedBeforeQueueDelta() async throws {
        let a = MobileHostFixture(name: "A"), b = MobileHostFixture(name: "B")
        let hosts = HostConnections(storage: nil,
            catalog: LibraryCatalog(libraryRoot: nil, filesRoot: nil), makeClient: { _ in a.client })
        var receipts: [UUID: GenerationReceipt] = [:]
        var queuePublished = false
        for fixture in [a, b] {
            hosts.add(fixture.preference, client: fixture.client)
            fixture.host.onCommand = { command in
                switch command {
                case .multiHost(.offer):
                    let isA = fixture === a
                    fixture.host.reply = .multiHost(.offer(HostOffer(refusal: nil,
                        queueSeconds: isA && queuePublished ? 60 : 0, preparationSeconds: 0,
                        executionSeconds: isA ? 60 : 90, memoryMargin: 1000, modelLoaded: true,
                        queueCount: isA && queuePublished ? 1 : 0, queueRevision: "test", physicalMemory: 10000)))
                case .multiHost(.submit(let job)):
                    let receipt = GenerationReceipt(requestID: job.request.requestID, digest: try! job.digest(),
                        batchID: UUID(), status: .accepted)
                    receipts[job.request.requestID] = receipt
                    fixture.host.reply = .multiHost(.receipt(receipt))
                case .multiHost(.receipt(let id)):
                    fixture.host.reply = receipts[id].map { .multiHost(.receipt($0)) }
                default: fixture.host.reply = nil
                }
            }
            await fixture.client.connect()
        }
        try await MobileHostFixture.settle { a.client.supportsMultiHost && b.client.supportsMultiHost }
        let dispatch = GenerationDispatch(hosts: hosts, root: nil)
        let first = StrictGeneration(request: GenerationRequest(modelID: "z-image-turbo-4bit", count: 1,
            settings: PromptDraft().settings))
        await dispatch.send(first, references: [])
        #expect(dispatch.submissions.first?.hostID == a.preference.id)
        #expect(dispatch.candidates().first { $0.id == a.preference.id }?.pendingSeconds == 60)
        let second = StrictGeneration(request: GenerationRequest(modelID: first.request.modelID, count: 1,
            settings: first.request.settings))
        await dispatch.send(second, references: [])
        #expect(dispatch.submissions.first { $0.id == second.request.requestID }?.hostID == b.preference.id)
        let accepted = try #require(receipts[first.request.requestID])
        let row = QueuedEntry(id: UUID(), batchID: try #require(accepted.batchID), batchIndex: 0,
            modelID: first.request.modelID, settings: first.request.settings)
        queuePublished = true
        try await a.host.announce(StateDelta.queue([row]), kind: .delta)
        try await MobileHostFixture.settle { a.client.snapshot?.queue.contains(row) == true }
        await dispatch.reconcile()
        await dispatch.refresh(first)
        let candidate = try #require(dispatch.candidates().first { $0.id == a.preference.id })
        #expect(candidate.pendingSeconds == 0)
        #expect(candidate.offer.queueSeconds == 60)
        #expect(candidate.offer.totalSeconds == 120)
        #expect(dispatch.submissions.first?.state == .accepted)
        await a.stop(); await b.stop()
        for fixture in [a, b] { await hosts.catalog.removeHost(fixture.preference.id) }
    }
}
