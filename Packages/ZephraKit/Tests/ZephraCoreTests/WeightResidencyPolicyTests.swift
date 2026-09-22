import Foundation
import Testing

@testable import ZephraCore

@Suite("WeightResidencyPolicy")
struct WeightResidencyPolicyTests {
    /// A model that can stream: peaks a 16 GB Mac cannot hold, with a streamed figure it can.
    static let streamable = MemoryFitTests.model(
        peak: 30_360_000_000, tiled: 26_070_000_000, streamed: 9_000_000_000)

    @Test("automatic streams exactly when the catalog says the model fits only streamed")
    func automaticFollowsTheFit() {
        let small = WeightResidencyPolicy(mode: .automatic, budget: MemoryFitTests.sixteenDefault)
        #expect(small.residency(for: Self.streamable) == .streamed)
        let roomy = WeightResidencyPolicy(
            mode: .automatic,
            budget: MemoryBudget(physicalMemory: MemoryFitTests.gigabytes(48), gpuWorkingSet: MemoryFitTests.gigabytes(36)))
        #expect(roomy.residency(for: Self.streamable) == .resident)
        // A model that fits only tiled stays resident: tiling is the cheaper lever.
        let tiledOnly = MemoryBudget(physicalMemory: MemoryFitTests.gigabytes(32), gpuWorkingSet: 27_000_000_000)
        #expect(WeightResidencyPolicy(mode: .automatic, budget: tiledOnly).residency(for: Self.streamable) == .resident)
    }

    @Test("a model with no streamed figure is resident under every mode")
    func unstreamableIsAlwaysResident() {
        // Over a fixture rather than over the catalog: every shipped family streams since the
        // 2026-09-13 Z-Image and klein measurements, so a loop over `all` would assert nothing
        // and pass. The rule still has to hold, because it is what a family added later
        // without a streamed path — or one measured and found not to help — relies on.
        let unstreamable = MemoryFitTests.model(peak: 30_360_000_000, tiled: 26_070_000_000)
        #expect(unstreamable.streamedPeakBytes == 0)
        for mode in WeightResidencyMode.allCases {
            let policy = WeightResidencyPolicy(mode: mode, budget: MemoryFitTests.sixteenDefault)
            #expect(policy.residency(for: unstreamable) == .resident, "\(mode.rawValue)")
        }
        #expect(ModelCatalog.all.allSatisfy { $0.streamedPeakBytes > 0 })
    }

    @Test("always and never ignore the machine for a model that can stream")
    func manualModesIgnoreTheMachine() {
        for budget in [MemoryFitTests.sixteenDefault, MemoryBudget(physicalMemory: MemoryFitTests.gigabytes(128))] {
            #expect(WeightResidencyPolicy(mode: .always, budget: budget).residency(for: Self.streamable) == .streamed)
            #expect(WeightResidencyPolicy(mode: .never, budget: budget).residency(for: Self.streamable) == .resident)
        }
    }

    @Test("a model too large even streamed is streamed rather than loaded resident to page")
    func tooLargeEvenStreamedIsStreamed() {
        // Loading a model that does not fit resident and letting the Mac page is how a 16 GB
        // mini aborted; streaming is the cheapest thing that can be tried, and the live guard
        // is what refuses the load when even that will not do.
        let huge = MemoryFitTests.model(peak: 60_000_000_000, tiled: 50_000_000_000, streamed: 20_000_000_000)
        #expect(WeightResidencyPolicy(mode: .automatic, budget: MemoryFitTests.sixteenDefault).residency(for: huge) == .streamed)
    }

    @Test("the mode survives a round trip through its stored raw value")
    func rawValueRoundTrip() {
        for mode in WeightResidencyMode.allCases {
            #expect(WeightResidencyMode(rawValue: mode.rawValue) == mode)
            #expect(!mode.displayName.isEmpty)
        }
        #expect(WeightResidencyMode.allCases.first == .automatic)
        #expect(WeightResidency(rawValue: "streamed") == .streamed)
    }

    @Test("a stream reading reports its rate and survives a pass that took no time")
    func readingRate() {
        #expect(WeightStreamReading(bytes: 16_000_000_000, seconds: 10).bytesPerSecond == 1_600_000_000)
        #expect(WeightStreamReading(bytes: 1, seconds: 0).bytesPerSecond == 0)
    }
}
