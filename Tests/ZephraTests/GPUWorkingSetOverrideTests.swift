import Foundation
import Testing
import ZephraCore

@testable import Zephra

/// `ZEPHRA_GPU_WORKING_SET_MB`, the hook that replays another Mac's GPU budget. The parsing is
/// pure and is what these pin; the Debug gate around it is compiled out here, since
/// `make test-app` only runs Debug, so the Release half of the claim rests on reading
/// `#if DEBUG` in the source, as `LaunchHookTests` does for the launch hooks.
@Suite("Replaying another Mac's GPU working set")
struct GPUWorkingSetOverrideTests {
    private static let thisMac = MemoryBudget(
        physicalMemory: 48 << 30, gpuWorkingSet: 36 << 30, wiredLimitMB: 40_000)

    @Test("the variable is read as mebibytes")
    func readsMebibytes() {
        #expect(
            GPUWorkingSetOverride.read(["ZEPHRA_GPU_WORKING_SET_MB": "12124"])
                == UInt64(12_124) * UInt64(MemoryUnits.mebibyte))
        #expect(
            GPUWorkingSetOverride.read(["ZEPHRA_GPU_WORKING_SET_MB": " 12124 "])
                == UInt64(12_124) * UInt64(MemoryUnits.mebibyte))
    }

    @Test("it replaces the working set and nothing else")
    func replacesOnlyTheWorkingSet() {
        let replayed = GPUWorkingSetOverride.replacing(
            Self.thisMac, environment: ["ZEPHRA_GPU_WORKING_SET_MB": "12124"])
        #expect(replayed.gpuWorkingSet == UInt64(12_124) * UInt64(MemoryUnits.mebibyte))
        #expect(replayed.bytes == Double(replayed.gpuWorkingSet))
        // The Mac's own RAM and its own sysctl stay: only what the policies measure against
        // moves, so the live guard and the Performance tab's command still describe this Mac.
        #expect(replayed.physicalMemory == Self.thisMac.physicalMemory)
        #expect(replayed.wiredLimitMB == Self.thisMac.wiredLimitMB)
    }

    @Test("an absent or malformed variable changes nothing")
    func leavesTheBudgetAlone() {
        for environment in [
            [:],
            ["ZEPHRA_GPU_WORKING_SET_MB": ""],
            ["ZEPHRA_GPU_WORKING_SET_MB": "  "],
            ["ZEPHRA_GPU_WORKING_SET_MB": "twelve"],
            ["ZEPHRA_GPU_WORKING_SET_MB": "12124MB"],
            ["ZEPHRA_GPU_WORKING_SET_MB": "12.5"],
            ["ZEPHRA_GPU_WORKING_SET_MB": "0"],
            ["ZEPHRA_GPU_WORKING_SET_MB": "-4096"],
            ["ZEPHRA_GPU_WORKING_SET": "12124"],
        ] as [[String: String]] {
            #expect(GPUWorkingSetOverride.read(environment) == nil)
            #expect(GPUWorkingSetOverride.replacing(Self.thisMac, environment: environment) == Self.thisMac)
        }
    }

    @Test("a replayed 16 GB Mac judges models as that Mac would")
    func thePoliciesFollowIt() {
        // The point of the hook: every policy reads `MemoryBudget.bytes`, so replacing the
        // working set is enough to make this Mac answer as bender does.
        let bender = GPUWorkingSetOverride.replacing(
            Self.thisMac, environment: ["ZEPHRA_GPU_WORKING_SET_MB": "12124"])
        let heavy = ModelCatalog.zImageTurbo8bit
        let here = MemoryFit(descriptor: heavy, budget: Self.thisMac)
        let there = MemoryFit(descriptor: heavy, budget: bender)
        #expect(here != there)
        #expect(there == .fitsStreamed)
    }
}
