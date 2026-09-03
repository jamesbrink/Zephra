import Foundation
import Testing

@testable import ZephraCore

@Suite("VAETilingPolicy")
struct VAETilingPolicyTests {
    static func gigabytes(_ count: UInt64) -> UInt64 { count * 1024 * 1024 * 1024 }

    static func policy(_ mode: VAETilingMode, _ gigabytes: UInt64) -> VAETilingPolicy {
        VAETilingPolicy(mode: mode, physicalMemory: Self.gigabytes(gigabytes))
    }

    @Test("a 48 GB Mac stays exact on both models")
    func roomyMacNeverTiles() {
        let policy = Self.policy(.automatic, 48)
        #expect(policy.tileSize(for: ModelCatalog.zImageTurbo8bit) == nil)
        #expect(policy.tileSize(for: ModelCatalog.zImageTurbo4bit) == nil)
    }

    @Test("a 24 GB Mac tiles for the 8-bit model and not for the 4-bit one")
    func mediumMacTilesForTheLargerModel() {
        let policy = Self.policy(.automatic, 24)
        #expect(policy.tileSize(for: ModelCatalog.zImageTurbo8bit) == VAETilingPolicy.latentTileEdge)
        #expect(policy.tileSize(for: ModelCatalog.zImageTurbo4bit) == nil)
    }

    @Test("a 16 GB Mac tiles for every model whose untiled peak is over its budget")
    func smallMacAlwaysTiles() {
        let policy = Self.policy(.automatic, 16)
        let budget = MemoryFit.budget(physicalMemory: ModelCatalogTests.gigabytes(16))
        for model in ModelCatalog.all {
            let expected: Int? =
                Double(model.peakBytes) > budget ? VAETilingPolicy.latentTileEdge : nil
            #expect(policy.tileSize(for: model) == expected, Comment(rawValue: model.id))
        }
        // Both Z-Image variants and Qwen-Image page untiled on a 16 GB Mac; klein 4-bit is the
        // first entry that does not, which is the point of it.
        #expect(policy.tileSize(for: ModelCatalog.zImageTurbo4bit) == VAETilingPolicy.latentTileEdge)
        #expect(policy.tileSize(for: ModelCatalog.flux2Klein4bit) == nil)
    }

    @Test("always and never ignore both the model and the machine")
    func manualModesIgnoreEverything() {
        for gigabytes in [UInt64(16), 48] {
            #expect(
                Self.policy(.always, gigabytes).tileSize(for: ModelCatalog.zImageTurbo4bit)
                    == VAETilingPolicy.latentTileEdge)
            #expect(Self.policy(.never, gigabytes).tileSize(for: ModelCatalog.zImageTurbo8bit) == nil)
        }
        #expect(Self.policy(.always, 48).tileSize(for: nil) == VAETilingPolicy.latentTileEdge)
    }

    @Test("automatic decodes untiled while no model is chosen")
    func noModelMeansNoTiling() {
        #expect(Self.policy(.automatic, 8).tileSize(for: nil) == nil)
    }

    @Test("automatic tiling matches what the catalog says about the fit")
    func automaticAgreesWithTheCatalog() {
        for gigabytes in [UInt64(8), 16, 24, 32, 48] {
            let memory = Self.gigabytes(gigabytes)
            let policy = VAETilingPolicy(mode: .automatic, physicalMemory: memory)
            for model in ModelCatalog.all {
                let comfortable = ModelCatalog.fitsComfortably(model, physicalMemory: memory)
                #expect((policy.tileSize(for: model) == nil) == comfortable)
            }
        }
    }

    @Test("the mode survives a round trip through its stored raw value")
    func rawValueRoundTrip() {
        for mode in VAETilingMode.allCases {
            #expect(VAETilingMode(rawValue: mode.rawValue) == mode)
            #expect(!mode.displayName.isEmpty)
        }
        #expect(VAETilingMode.allCases.first == .automatic)
        #expect(VAETilingMode(rawValue: "sideways") == nil)
    }
}
