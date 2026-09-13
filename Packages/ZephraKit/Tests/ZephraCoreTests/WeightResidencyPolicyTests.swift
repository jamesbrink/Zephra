import Foundation
import Testing

@testable import ZephraCore

@Suite("WeightResidencyPolicy")
struct WeightResidencyPolicyTests {
    /// A model that can stream: Qwen-Image's peaks with a streamed figure a 16 GB Mac holds.
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
        for mode in WeightResidencyMode.allCases {
            let policy = WeightResidencyPolicy(mode: mode, budget: MemoryFitTests.sixteenDefault)
            for model in ModelCatalog.all where model.streamedPeakBytes == 0 {
                #expect(policy.residency(for: model) == .resident, Comment(rawValue: model.id))
            }
        }
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
