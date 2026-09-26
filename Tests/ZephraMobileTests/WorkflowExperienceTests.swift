import Foundation
import Testing
import ZephraCore
import ZephraLinkClient
import ZephraLinkProtocol
@testable import ZephraMobile

@MainActor @Suite("Mobile workflow scope, gallery density and Today clarity")
struct WorkflowExperienceTests {
    @Test func autoHistoryMergesLiveEnabledHostsChronologically() async throws {
        let a = MobileHostFixture(name: "A"), b = MobileHostFixture(name: "B")
        let hosts = HostConnections(storage: nil, catalog: LibraryCatalog(libraryRoot: nil, filesRoot: nil), makeClient: { _ in a.client })
        let old = PromptHistoryEntry(prompt: "older on A", createdAt: Date(timeIntervalSince1970: 1))
        let new = PromptHistoryEntry(prompt: "newer on B", createdAt: Date(timeIntervalSince1970: 2))
        for fixture in [a, b] {
            fixture.host.world?.workflow = true
            fixture.host.onCommand = { command in
                if case .workflow(.history) = command { fixture.host.reply = .workflow(.history([fixture === a ? old : new])) }
                else { fixture.host.reply = .ok }
            }
            hosts.add(fixture.preference, client: fixture.client)
            await fixture.client.connect()
        }
        try await MobileHostFixture.settle { a.client.supportsWorkflow && b.client.supportsWorkflow }
        let dispatch = GenerationDispatch(hosts: hosts, root: nil)
        hosts.watch(a.preference.id)
        let history = MobilePromptHistory()
        await history.refresh(dispatch)
        #expect(history.entries.map(\.prompt) == [new.prompt, old.prompt], "Auto reads every live enabled Mac, independent of the watched Mac")
        dispatch.destination = a.preference.id
        await history.refresh(dispatch)
        #expect(history.entries.map(\.prompt) == [old.prompt])
        dispatch.destination = nil
        var disabled = b.preference; disabled.enabled = false; hosts.update(disabled)
        await history.refresh(dispatch)
        #expect(history.entries.map(\.prompt) == [old.prompt])
        await a.stop(); await b.stop()
        for fixture in [a, b] { await hosts.catalog.removeHost(fixture.preference.id) }
    }
    @Test func galleryPinchDirectionAndBounds() {
        #expect(GalleryDensity.columns(start: 3, magnification: 1.5) == 2)
        #expect(GalleryDensity.columns(start: 3, magnification: 0.6) == 5)
        #expect(GalleryDensity.columns(start: 3, magnification: 10) == 1)
        #expect(GalleryDensity.columns(start: 3, magnification: 0.01) == 6)
        #expect(GalleryDensity.columns(start: 3, magnification: .nan) == 3)
    }
    @Test func successfulReceiptsAreNotRenderedTwiceAndUncertaintyNeverDisappears() {
        let fixture = MobileHostFixture(name: "A")
        let now = Date()
        let records = [Submission.State.completed, .accepted, .unknown, .sending, .rejected, .interrupted].map { state in
            Submission(generation: StrictGeneration(request: GenerationRequest(modelID: "model", count: 1, settings: PromptDraft().settings)),
                hostID: fixture.preference.id, hostName: "A", state: state, createdAt: state == .unknown ? now.addingTimeInterval(-172800) : now)
        }
        let visible = SubmissionAttention.visible(records, now: now)
        #expect(visible.count == 4)
        #expect(visible.contains { $0.state == .unknown })
        #expect(!visible.contains { $0.state == .completed || $0.state == .accepted })
    }
}
