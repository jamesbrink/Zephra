import Foundation
import Testing
@testable import ZephraLinkClient

@MainActor @Suite("User transfers get priority without starving queued work")
struct TransferPriorityTests {
    @Test("References, opened media and visible thumbnails precede background bytes")
    func orderedPriorities() async throws {
        let admission = TransferAdmission(limit: 1), blocker = UUID()
        try await admission.enter(blocker)
        var order: [TransferPriority] = []
        var jobs: [Task<Void, any Error>] = []
        for priority in [TransferPriority.background, .visibleThumbnail, .openedMedia, .reference] {
            let owner = UUID()
            jobs.append(Task {
                try await admission.enter(owner, priority: priority)
                order.append(priority)
                admission.leave(owner)
            })
            while admission.waitingCount < jobs.count { await Task.yield() }
        }
        admission.leave(blocker)
        for job in jobs { try await job.value }
        #expect(order == [.reference, .openedMedia, .visibleThumbnail, .background])
    }

    @Test("An old background transfer is admitted after eight newer priority grants")
    func starvationBound() async throws {
        let admission = TransferAdmission(limit: 1), blocker = UUID()
        try await admission.enter(blocker)
        var order: [Int] = []
        var jobs: [Task<Void, any Error>] = []
        for index in 0..<13 {
            let owner = UUID()
            jobs.append(Task {
                try await admission.enter(owner, priority: index == 0 ? .background : .reference)
                order.append(index)
                admission.leave(owner)
            })
            while admission.waitingCount < jobs.count { await Task.yield() }
        }
        admission.leave(blocker)
        for job in jobs { try await job.value }
        #expect(order.firstIndex(of: 0) == 8)
        #expect(Set(order).count == 13)
    }
}
