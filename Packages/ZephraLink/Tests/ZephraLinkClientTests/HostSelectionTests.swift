import Foundation
import Testing
import ZephraLinkClient
import ZephraLinkProtocol

@Suite("Automatic host selection keeps exact workloads on fresh eligible hosts")
struct HostSelectionTests {
    private func candidate(_ id: String, queue: Double? = 0, preparation: Double? = 0,
                           execution: Double? = 10, count: Int = 0, loaded: Bool = true,
                           margin: Double = 1, age: Double = 0, pending: Double = 0,
                           refusal: String? = nil) -> HostCandidate {
        .init(id: HostID(keys: DevicePublicKeys(keyAgreement: Data(), signing: Data(id.utf8))), offer: HostOffer(refusal: refusal, queueSeconds: queue,
            preparationSeconds: preparation, executionSeconds: execution, memoryMargin: margin,
            modelLoaded: loaded, queueCount: count, queueRevision: "q", physicalMemory: 32_000_000_000),
            age: age, pendingSeconds: pending)
    }

    @Test("Missing models, stale offers, invalid estimates and insufficient memory are excluded")
    func eligibility() {
        let invalid = [candidate("missing", refusal: "Model not installed"), candidate("stale", age: 6),
            candidate("memory", margin: -1), candidate("nan", execution: .nan),
            candidate("negative", queue: -1), candidate("infinite", preparation: .infinity)]
        #expect(HostSelection.best(invalid) == nil)
        #expect(HostSelection.best(invalid + [candidate("ready")])?.id == candidate("ready").id)
    }

    @Test("Completion cost includes loading, queued work and unreflected accepted submissions")
    func completionCost() {
        let fastBusy = candidate("fast", queue: 100, execution: 5, count: 2)
        let idle = candidate("idle", execution: 20)
        #expect(HostSelection.best([fastBusy, idle])?.id == idle.id)
        #expect(HostSelection.best([candidate("first", pending: 60), idle])?.id == idle.id)
    }

    @Test("Unknown estimates rank consistently regardless of discovery order")
    func permutations() {
        let a = candidate("a", queue: 10, preparation: nil, count: 1, margin: 3)
        let b = candidate("b", queue: nil, preparation: nil, count: 1, margin: 2)
        let c = candidate("c", queue: 20, preparation: nil, count: 1, margin: 4)
        for list in [[a,b,c], [a,c,b], [b,a,c], [b,c,a], [c,a,b], [c,b,a]] {
            #expect(HostSelection.best(list)?.id == a.id)
        }
    }

    @Test("Small estimate fluctuations retain the recommendation, significant gains switch")
    func hysteresis() {
        let old = candidate("old", execution: 100)
        #expect(HostSelection.best([old, candidate("new", execution: 90)], previous: old.id)?.id == old.id)
        #expect(HostSelection.best([old, candidate("new", execution: 70)], previous: old.id)?.id == candidate("new").id)
        #expect(HostSelection.best([candidate("old", execution: 100, age: 6), candidate("new")],
            previous: old.id)?.id == candidate("new").id)
    }
    @Test func explanationMatchesRanking() {
        let known = candidate("known", execution: 100, margin: 4)
        let unknown = candidate("unknown", execution: nil, margin: 2)
        #expect(HostSelection.best([known, unknown])?.id == known.id)
        #expect(HostSelection.reason(known.offer, selected: known.id, candidates: [known, unknown])
            == "Model loaded · ready now")
        let faster = candidate("faster", execution: 90)
        #expect(HostSelection.reason(known.offer, selected: known.id, candidates: [known, faster])
            == "Keeping this Mac · estimated finish times are close")
        #expect(HostSelection.reason(faster.offer, selected: faster.id, candidates: [known, faster])
            == "Shortest estimated wait and generation time")
    }

}
