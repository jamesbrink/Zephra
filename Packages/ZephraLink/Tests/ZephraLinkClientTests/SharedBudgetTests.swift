import Foundation
import Testing
@testable import ZephraLinkClient

@MainActor
@Suite("Multi-host transfer budgets are shared and cancellation-aware")
struct SharedBudgetTests {
    @Test("Eight owners share one byte limit and one owner releasing cannot free another's bytes")
    func byteBudget() {
        let budget = BlobBudget(limit: 80, fileLimit: 20)
        let owners = (0..<8).map { _ in UUID() }, blobs = (0..<8).map { _ in UUID() }
        for index in 0..<8 { #expect(budget.reserve(owner: owners[index], blob: blobs[index], bytes: 10)) }
        #expect(!budget.reserve(owner: UUID(), blob: UUID(), bytes: 1))
        budget.release(owner: owners[0])
        #expect(budget.reserve(owner: UUID(), blob: UUID(), bytes: 10))
        #expect(!budget.reserve(owner: owners[1], blob: UUID(), bytes: 21))
    }
    @Test("A cancelled waiter does not take another host's active transfer slot")
    func cancellation() async throws {
        let admission = TransferAdmission(limit: 2)
        let a = UUID(), b = UUID(), c = UUID()
        try await admission.enter(a)
        try await admission.enter(b)
        var entered = false
        let waiter = Task { try await admission.enter(c); entered = true }
        for _ in 0..<4 { await Task.yield() }
        #expect(!entered)
        waiter.cancel()
        do { try await waiter.value; Issue.record("Cancelled waiter entered") } catch is CancellationError {} catch { throw error }
        admission.leave(a)
        try await admission.enter(c)
        admission.leave(b); admission.leave(c)
    }
}
