import Testing

@testable import ZephraCore

@Suite("The check before a load and before a run")
struct MemoryGuardTests {
    /// The 16 GB M4 mini as macOS sets it up: 12124 MB of working set.
    static let guardian = MemoryGuard(budget: MemoryFitTests.sixteenDefault)

    static func machine(freeGigabytes: Double) -> MachineMemory {
        MachineMemory(
            physicalBytes: Int64(MemoryFitTests.gigabytes(16)),
            availableBytes: Int64(freeGigabytes * 1_000_000_000))
    }

    static func settings(width: Int, height: Int, frames: Int) -> GenerationSettings {
        GenerationSettings(
            prompt: "a test", size: ImageSize(width: width, height: height), steps: 8,
            guidance: 0, seed: 1, frames: frames)
    }

    @Test("with no reading to be had the budget alone decides, and it refuses what cannot fit")
    func theBudgetAloneDecidesWithoutAReading() {
        // Z-Image 8-bit tiled is 17.9 GB against a 12.7 GB working set: the load that aborted
        // a 16 GB mini on 2026-09-13, refused here before Metal is asked for a byte.
        let refused = Self.guardian.loadShortfall(
            for: ModelCatalog.zImageTurbo8bit, residency: .resident, tile: 64, machine: nil,
            runtime: .zero)
        #expect(refused?.phase == .load)
        #expect(refused?.neededBytes == ModelCatalog.zImageTurbo8bit.tiledPeakBytes)
        #expect(refused?.freeBytes == Int64(MemoryFitTests.sixteenDefault.bytes))
        // klein 4-bit fits that budget, so a machine nobody can read is no reason to refuse it.
        #expect(
            Self.guardian.loadShortfall(
                for: ModelCatalog.flux2Klein4bit, residency: .resident, tile: nil, machine: nil,
                runtime: .zero) == nil)
    }

    @Test("Zephra's own active and cached bytes count as free, since the load releases them")
    func ourOwnMemoryIsCountedBack() {
        let model = ModelCatalog.flux2Klein4bit
        // 2 GB free on the machine with a model of our own still in: too little on its face.
        let busy = Self.machine(freeGigabytes: 2)
        #expect(
            Self.guardian.loadShortfall(
                for: model, residency: .resident, tile: nil, machine: busy, runtime: .zero) != nil)
        // The same machine, with the 10.5 GB in question Zephra's own: the switch releases it
        // before it reads the next model, so the load is admitted.
        let ours = MemorySnapshot(
            activeBytes: 9_500_000_000, cacheBytes: 1_000_000_000, peakBytes: 10_500_000_000)
        #expect(
            Self.guardian.loadShortfall(
                for: model, residency: .resident, tile: nil, machine: busy, runtime: ours) == nil)
    }

    @Test("a streamed load is charged the streamed peak, not the resident one")
    func streamedLoadsAreChargedTheStreamedPeak() {
        let model = ModelCatalog.ltx2Distilled4bit
        let roomy = Self.machine(freeGigabytes: 11)
        #expect(
            Self.guardian.loadShortfall(
                for: model, residency: .streamed, tile: 64, machine: roomy, runtime: .zero) == nil)
        // Held resident the same model wants 23.4 GB, and the same Mac cannot have it.
        let refused = Self.guardian.loadShortfall(
            for: model, residency: .resident, tile: 64, machine: roomy, runtime: .zero)
        #expect(refused?.neededBytes == model.tiledPeakBytes)
        // Held resident by choice on a Mac that could stream it: the remedy is the preference.
        #expect(refused?.remedy == .streamFromDisk)
    }

    @Test("a machine that is simply full is asked for room rather than sent to Settings")
    func aBusyMachineIsAskedForRoom() {
        let refused = Self.guardian.loadShortfall(
            for: ModelCatalog.ltx2Distilled4bit, residency: .streamed, tile: 64,
            machine: Self.machine(freeGigabytes: 2), runtime: .zero)
        #expect(refused?.remedy == .quitOtherApps)
        #expect(refused?.sentence.hasSuffix("Quit other apps and retry.") == true)
    }

    @Test("what a run costs is the transient, and it grows with pixels times frames")
    func theRunChargesTheTransientScaledByTheRequest() {
        let model = ModelCatalog.ltx2Distilled4bit
        let held = MemorySnapshot(
            activeBytes: 5_737_000_000, cacheBytes: 0, peakBytes: 5_737_000_000)
        let short = Self.guardian.transientBytes(
            of: model, residency: .streamed, tile: 64,
            settings: Self.settings(width: 768, height: 512, frames: 49), runtime: held)
        let long = Self.guardian.transientBytes(
            of: model, residency: .streamed, tile: 64,
            settings: Self.settings(width: 960, height: 576, frames: 121), runtime: held)
        // 960 x 576 x 121 against 768 x 512 x 49 is three and a half times the work, and the
        // estimate is linear in exactly that, which is what makes a long clip refusable when
        // the clip the peak was measured at is not.
        let ratio = Double(long) / Double(short)
        #expect(ratio > 3.4 && ratio < 3.6)
        // A machine with room for the short clip and not the long one answers both ways.
        let machine = Self.machine(freeGigabytes: 5)
        #expect(
            Self.guardian.runShortfall(
                for: model, residency: .streamed, tile: 64,
                settings: Self.settings(width: 768, height: 512, frames: 49), machine: machine,
                runtime: held) == nil)
        let refused = Self.guardian.runShortfall(
            for: model, residency: .streamed, tile: 64,
            settings: Self.settings(width: 960, height: 576, frames: 121), machine: machine,
            runtime: held)
        #expect(refused?.phase == .run)
        #expect(refused?.neededBytes == long)
    }

    @Test("a streamed run before MLX has allocated is charged its own held figure, not the resident one")
    func aStreamedRunIsChargedAgainstItsStreamedHeldFigure() {
        // No allocator reading yet, so the held figure comes off the descriptor. It has to be
        // `streamedResidentBytes`: `residentBytes` is 19160 MB here against a 10010 MB streamed
        // peak, so subtracting it would floor the transient at zero and admit every streamed
        // run on any machine. The answer is the measured 10010 - 5730 MB at the default size.
        let model = ModelCatalog.ltx2Distilled4bit
        let size = model.capabilities.defaultSize
        let atDefault = Self.settings(
            width: size.width, height: size.height, frames: model.capabilities.defaultFrames)
        let charged = Self.guardian.transientBytes(
            of: model, residency: .streamed, tile: 64, settings: atDefault, runtime: .zero)
        #expect(charged == model.streamedPeakBytes - model.streamedResidentBytes)
        #expect(charged > 0)
        // And that is what refuses a streamed run on a Mac with 400 MB free, which before the
        // held figure was measured was admitted.
        let starved = MachineMemory(
            physicalBytes: Int64(MemoryFitTests.gigabytes(16)), availableBytes: 400_000_000)
        let refused = Self.guardian.runShortfall(
            for: model, residency: .streamed, tile: 64, settings: atDefault, machine: starved,
            runtime: .zero)
        #expect(refused?.phase == .run)
        #expect(refused?.neededBytes == charged)
        // A live allocator reading still wins: it is the truth about this load.
        let held = MemorySnapshot(
            activeBytes: 6_000_000_000, cacheBytes: 0, peakBytes: 6_000_000_000)
        #expect(
            Self.guardian.transientBytes(
                of: model, residency: .streamed, tile: 64, settings: atDefault, runtime: held)
                == model.streamedPeakBytes - 6_000_000_000)
    }

    @Test("a streaming family with no held figure measured is charged its whole streamed peak")
    func anUnmeasuredHeldFigureChargesTheWholePeak() {
        // The conservative fallback, which is what a family added later gets until its live
        // figure is measured: better to refuse a run that would have fitted than to admit one
        // that aborts the app.
        let unmeasured = MemoryFitTests.model(
            peak: 30_000_000_000, tiled: 26_000_000_000, streamed: 9_000_000_000)
        #expect(unmeasured.streamedResidentBytes == 0)
        let size = unmeasured.capabilities.defaultSize
        #expect(
            Self.guardian.transientBytes(
                of: unmeasured, residency: .streamed, tile: 64,
                settings: Self.settings(width: size.width, height: size.height, frames: 1),
                runtime: .zero) == unmeasured.streamedPeakBytes)
    }

    @Test("a run with no reading of the machine refuses nothing: the load already passed")
    func aRunWithoutAReadingRefusesNothing() {
        #expect(
            Self.guardian.runShortfall(
                for: ModelCatalog.ltx2Distilled4bit, residency: .streamed, tile: 64,
                settings: Self.settings(width: 1920, height: 1088, frames: 241), machine: nil,
                runtime: .zero) == nil)
    }
}
