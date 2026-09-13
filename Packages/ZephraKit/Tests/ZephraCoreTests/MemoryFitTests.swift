import Foundation
import Testing

@testable import ZephraCore

@Suite("MemoryFit follows the GPU's working set, not a fraction of RAM")
struct MemoryFitTests {
    static func gigabytes(_ count: UInt64) -> UInt64 { count * 1024 * 1024 * 1024 }
    static func megabytes(_ count: UInt64) -> UInt64 { count * 1024 * 1024 }

    /// A 16 GB Mac as macOS sets it up: Metal reports 12124 MB, measured on an M4 mini.
    static let sixteenDefault = MemoryBudget(
        physicalMemory: gigabytes(16), gpuWorkingSet: megabytes(12124))
    /// The same Mac after `sudo sysctl -w iogpu.wired_limit_mb=16384`.
    static let sixteenRaised = MemoryBudget(
        physicalMemory: gigabytes(16), gpuWorkingSet: megabytes(16384), wiredLimitMB: 16384)

    /// A descriptor with the given peaks and nothing else worth reading.
    static func model(peak: Int64, tiled: Int64, streamed: Int64 = 0) -> ModelDescriptor {
        ModelDescriptor(
            id: "test", displayName: "Test", variantName: nil, backend: .zImage,
            source: .localDirectory(URL(filePath: "/tmp/test")), quantization: .int4,
            downloadBytes: 0, residentBytes: 1, peakBytes: peak, tiledPeakBytes: tiled,
            streamedPeakBytes: streamed, maxPromptTokens: 512,
            capabilities: ModelCatalog.zImageTurbo4bit.capabilities, builtBytes: 0,
            adapters: [])
    }

    @Test("the budget is what the GPU may keep, and the fallback is four fifths of RAM")
    func budgetIsTheWorkingSet() {
        #expect(Self.sixteenDefault.bytes == Double(Self.megabytes(12124)))
        #expect(!Self.sixteenDefault.isWiredLimitRaised)
        #expect(Self.sixteenRaised.isWiredLimitRaised)
        let fallback = MemoryBudget(physicalMemory: Self.gigabytes(16))
        #expect(fallback.gpuWorkingSet == UInt64(Double(Self.gigabytes(16)) * 0.8))
        #expect(fallback.physicalMemoryMB == 16384)
        #expect(
            MemoryBudget.wiredLimitCommand(megabytes: 16384)
                == "sudo sysctl -w iogpu.wired_limit_mb=16384")
    }

    @Test("raising the wired limit moves a model from tight to tiled on the same Mac")
    func raisedLimitChangesTheVerdict() {
        // klein 8-bit: 15.3 GB untiled, 10.9 GB tiled. Tiled it fits the default 12.7 GB;
        // untiled it needs the raised 17.2 GB.
        let klein = ModelCatalog.flux2Klein8bit
        #expect(MemoryFit(descriptor: klein, budget: Self.sixteenDefault) == .fitsTiled)
        #expect(MemoryFit(descriptor: klein, budget: Self.sixteenRaised) == .fits)
        // Z-Image 4-bit: 17.8 GB untiled, 12.0 GB tiled. The raised budget does not reach the
        // untiled peak, so it stays tiled.
        let turbo = ModelCatalog.zImageTurbo4bit
        #expect(MemoryFit(descriptor: turbo, budget: Self.sixteenDefault) == .fitsTiled)
        #expect(MemoryFit(descriptor: turbo, budget: Self.sixteenRaised) == .fitsTiled)
    }

    @Test("a tight verdict names the working set that would clear it")
    func tightNamesTheWorkingSet() {
        // Qwen-Image's peaks without its streamed figure: what the catalog said before
        // streaming, and what a family that cannot stream says still.
        let unstreamable = Self.model(peak: 30_360_000_000, tiled: 26_070_000_000)
        guard case .tight(let needed) = MemoryFit(descriptor: unstreamable, budget: Self.sixteenDefault)
        else {
            Issue.record("a 26 GB tiled peak does not fit a 16 GB Mac's default working set")
            return
        }
        #expect(needed == unstreamable.tiledPeakBytes)
        // Feeding that figure back as the working set is exactly enough.
        let enough = MemoryBudget(physicalMemory: Self.gigabytes(48), gpuWorkingSet: UInt64(needed))
        #expect(MemoryFit(descriptor: unstreamable, budget: enough) == .fitsTiled)
    }

    @Test("the raise-the-limit hint appears only when RAM would actually hold the leanest peak")
    func hintOnlyWhenRaisingHelps() {
        // klein 8-bit's tiled peak is under 16 GB of RAM; a 26 GB tiled peak from a family
        // that cannot stream is not, and there is no leaner figure to fall back on.
        #expect(
            MemoryFit.wouldFitWithWiredLimitRaised(ModelCatalog.flux2Klein8bit, budget: Self.sixteenDefault))
        #expect(
            !MemoryFit.wouldFitWithWiredLimitRaised(
                Self.model(peak: 30_360_000_000, tiled: 26_070_000_000), budget: Self.sixteenDefault))
        // A 32 GB Mac's default working set (about 22.9 GB) is under a 26.1 GB tiled peak,
        // and the RAM is over it: this is the Mac the hint is for, when the model cannot
        // stream instead.
        let unstreamable = Self.model(peak: 30_360_000_000, tiled: 26_070_000_000)
        let thirtyTwo = MemoryBudget(physicalMemory: Self.gigabytes(32), gpuWorkingSet: Self.megabytes(22_900))
        guard case .tight = MemoryFit(descriptor: unstreamable, budget: thirtyTwo) else {
            Issue.record("a 26 GB tiled peak is over a 32 GB Mac's default working set")
            return
        }
        #expect(MemoryFit.wouldFitWithWiredLimitRaised(unstreamable, budget: thirtyTwo))
        // Qwen-Image itself streams there, so the picker offers it rather than the hint.
        #expect(MemoryFit(descriptor: ModelCatalog.qwenImage2512_4bit, budget: thirtyTwo) == .fitsStreamed)
    }

    @Test("tight quotes the leanest figure, which is the streamed one where the family streams")
    func tightQuotesTheLeanestFigure() {
        // A family that streams is asked for its streamed peak, not its tiled one: the tiled
        // figure would tell a person to find 26 GB for a model Zephra would never load that way.
        let streams = Self.model(
            peak: 30_000_000_000, tiled: 26_000_000_000, streamed: 20_000_000_000)
        guard case .tight(let needed) = MemoryFit(descriptor: streams, budget: Self.sixteenDefault)
        else {
            Issue.record("a 20 GB streamed peak does not fit a 16 GB Mac's default working set")
            return
        }
        #expect(needed == streams.streamedPeakBytes)
        // And a Mac with 32 GB of RAM could reach that streamed peak by raising the limit,
        // where the tiled figure would have said no.
        let thirtyTwo = MemoryBudget(physicalMemory: Self.gigabytes(32), gpuWorkingSet: Self.megabytes(22_900))
        #expect(MemoryFit.wouldFitWithWiredLimitRaised(streams, budget: thirtyTwo))
    }

    @Test("a streamed figure is offered after tiling and before giving up, and never when zero")
    func streamedComesAfterTiling() {
        let model = Self.model(peak: 30_000_000_000, tiled: 26_000_000_000, streamed: 9_000_000_000)
        let fit = MemoryFit(descriptor: model, budget: Self.sixteenDefault)
        #expect(fit == .fitsStreamed)
        #expect(fit.isSelectable && fit.requiresStreaming && fit.requiresTiling)
        let roomy = MemoryBudget(physicalMemory: Self.gigabytes(48), gpuWorkingSet: Self.gigabytes(36))
        #expect(MemoryFit(descriptor: model, budget: roomy) == .fits)
        let unstreamable = Self.model(peak: 30_000_000_000, tiled: 26_000_000_000)
        guard case .tight = MemoryFit(descriptor: unstreamable, budget: Self.sixteenDefault) else {
            Issue.record("a model with no streamed figure cannot be offered streamed")
            return
        }
        // A streamed peak over the budget is still tight, not streamed.
        let tooBig = Self.model(peak: 30_000_000_000, tiled: 26_000_000_000, streamed: 14_000_000_000)
        #expect(!MemoryFit(descriptor: tooBig, budget: Self.sixteenDefault).isSelectable)
    }
}
