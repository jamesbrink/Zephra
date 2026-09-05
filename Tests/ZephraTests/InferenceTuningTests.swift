import Testing
import ZephraCore

@testable import Zephra

@Suite("The memory ceilings the runtime is tuned to")
struct InferenceTuningTests {
    private let gigabyte = 1 << 30

    @Test("the cache is a sixth of RAM, capped at 8 GB")
    func cacheIsASixthOfRAMCappedAtEightGB() {
        let small = InferenceTuning.forThisMachine(
            budget: MemoryBudget(physicalMemory: UInt64(24 * gigabyte)))
        #expect(small.cacheLimitBytes == 4 * gigabyte)
        let large = InferenceTuning.forThisMachine(
            budget: MemoryBudget(physicalMemory: UInt64(128 * gigabyte)))
        #expect(large.cacheLimitBytes == 8 * gigabyte)
    }

    @Test("the memory limit follows the GPU's working set, not a fraction of RAM")
    func memoryLimitFollowsTheWorkingSet() {
        let budget = MemoryBudget(
            physicalMemory: UInt64(16 * gigabyte), gpuWorkingSet: UInt64(12 * gigabyte))
        let tuning = InferenceTuning.forThisMachine(budget: budget)
        #expect(tuning.memoryLimitBytes == 12 * gigabyte)
    }

    @Test("a budget built from RAM alone assumes four fifths of it for the GPU")
    func ramOnlyBudgetAssumesFourFifths() {
        let tuning = InferenceTuning.forThisMachine(
            budget: MemoryBudget(physicalMemory: UInt64(10 * gigabyte)))
        #expect(tuning.memoryLimitBytes == 8 * gigabyte)
    }

    @Test("a hand-picked cache ceiling is brought inside the machine's bounds")
    func clampedMBStaysInsideTheBounds() {
        let bounds = InferenceTuning.cacheLimitBoundsMB
        #expect(InferenceTuning.clampedMB(1) == bounds.lowerBound)
        #expect(InferenceTuning.clampedMB(Int.max) == bounds.upperBound)
        let inside = (bounds.lowerBound + bounds.upperBound) / 2
        #expect(InferenceTuning.clampedMB(inside) == inside)
    }

    @Test("the recommendation is inside its own bounds and counts a megabyte as 2^20 bytes")
    func recommendationIsInsideItsOwnBounds() {
        #expect(InferenceTuning.cacheLimitBoundsMB.contains(InferenceTuning.recommendedCacheLimitMB))
        #expect(InferenceTuning.bytesPerMB == 1_048_576)
    }
}
