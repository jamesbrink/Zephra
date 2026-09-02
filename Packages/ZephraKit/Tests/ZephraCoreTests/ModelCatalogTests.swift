import Foundation
import Testing

@testable import ZephraCore

@Suite("ModelCatalog")
struct ModelCatalogTests {
    /// `n` gibibytes, the unit `ProcessInfo.physicalMemory` reports a Mac's RAM in.
    static func gigabytes(_ count: UInt64) -> UInt64 { count * 1024 * 1024 * 1024 }

    @Test("an 8 GB Mac is offered nothing: even the tiled 4-bit peak is over its budget")
    func eightGigabytesFitsNothing() {
        let memory = Self.gigabytes(8)
        #expect(ModelCatalog.fitting(physicalMemory: memory).isEmpty)
        for model in ModelCatalog.all {
            #expect(!ModelCatalog.fit(model, physicalMemory: memory).runsAtDefaultSize)
        }
    }

    @Test("a 16 GB Mac is offered the 4-bit Turbo model, tiled, but not the 8-bit one")
    func sixteenGigabytesFitsOnlyFourBit() {
        let memory = Self.gigabytes(16)
        let fitting = ModelCatalog.fitting(physicalMemory: memory)
        #expect(!fitting.contains(ModelCatalog.zImageTurbo8bit))
        #expect(fitting.contains(ModelCatalog.zImageTurbo4bit))
        // 12.0 GB tiled against a 13.7 GB budget; 17.8 GB untiled is well over it.
        #expect(ModelCatalog.fit(ModelCatalog.zImageTurbo4bit, physicalMemory: memory) == .fitsTiled)
        #expect(!ModelCatalog.fitsComfortably(ModelCatalog.zImageTurbo4bit, physicalMemory: memory))
    }

    @Test("a 32 GB Mac is offered both Turbo variants, and neither needs tiling")
    func thirtyTwoGigabytesFitsBoth() {
        let memory = Self.gigabytes(32)
        let fitting = ModelCatalog.fitting(physicalMemory: memory)
        #expect(fitting.contains(ModelCatalog.zImageTurbo8bit))
        #expect(fitting.contains(ModelCatalog.zImageTurbo4bit))
        for model in ModelCatalog.all {
            #expect(ModelCatalog.fit(model, physicalMemory: memory) == .fits)
            #expect(ModelCatalog.fitsComfortably(model, physicalMemory: memory))
        }
    }

    @Test("a 24 GB Mac runs the 4-bit model exactly and the 8-bit one only tiled")
    func twentyFourGigabytesNeedsTilingForEightBit() {
        let memory = Self.gigabytes(24)
        #expect(ModelCatalog.fit(ModelCatalog.zImageTurbo4bit, physicalMemory: memory) == .fits)
        // 23.5 GB untiled is over the 19.3 GB budget; 17.7 GB tiled is under it.
        #expect(ModelCatalog.fit(ModelCatalog.zImageTurbo8bit, physicalMemory: memory) == .fitsTiled)
        #expect(ModelCatalog.fitting(physicalMemory: memory).count == 2)
    }

    @Test("a Mac too small for a model is told how much memory it would take")
    func tightReportsWhatItWouldNeed() {
        let fit = ModelCatalog.fit(ModelCatalog.zImageTurbo8bit, physicalMemory: Self.gigabytes(8))
        guard case .tight(let needed) = fit else {
            Issue.record("expected the 8-bit model not to fit on an 8 GB Mac")
            return
        }
        // The tiled peak divided by the working-set fraction: what the machine would need.
        #expect(needed == 22_100_000_000)
        #expect(
            ModelCatalog.fit(ModelCatalog.zImageTurbo8bit, physicalMemory: UInt64(needed))
                == .fitsTiled)
    }

    @Test("every peak is above its resident size, and tiling never costs more than not tiling")
    func peaksAreOrdered() {
        for model in ModelCatalog.all {
            #expect(model.peakBytes > model.residentBytes)
            #expect(model.tiledPeakBytes > model.residentBytes)
            #expect(model.tiledPeakBytes <= model.peakBytes)
        }
    }

    @Test("the 8-bit model stays the default, and the 4-bit variant is listed after it")
    func fourBitIsListedSecond() {
        #expect(ModelCatalog.default == ModelCatalog.zImageTurbo8bit)
        #expect(ModelCatalog.all == [ModelCatalog.zImageTurbo8bit, ModelCatalog.zImageTurbo4bit])
    }

    @Test("the 4-bit variant is built locally, so it downloads nothing")
    func fourBitIsLocal() {
        let descriptor = ModelCatalog.zImageTurbo4bit
        #expect(!descriptor.source.requiresDownload)
        #expect(descriptor.downloadBytes == 0)
        #expect(descriptor.quantization == .int4)
        #expect(descriptor.fullName == "Z-Image Turbo · 4-bit")
        #expect(descriptor.maxPromptTokens == ModelCatalog.zImageTurbo8bit.maxPromptTokens)
        #expect(descriptor.capabilities == ModelCatalog.zImageTurbo8bit.capabilities)
        #expect(
            descriptor.source
                == .localDirectory(
                    ModelCatalog.localModelsDirectory.appending(path: "z-image-turbo-4bit")))
    }

    @Test("every model can be looked up by its own identifier")
    func descriptorRoundTrip() {
        for descriptor in ModelCatalog.all {
            #expect(ModelCatalog.descriptor(id: descriptor.id) == descriptor)
        }
        #expect(ModelCatalog.descriptor(id: "not-a-model") == nil)
    }

    @Test("the default model is one of the listed models")
    func defaultIsListed() {
        #expect(ModelCatalog.all.contains(ModelCatalog.default))
    }

    @Test("a first launch starts on the largest model the Mac can actually run")
    func defaultFollowsTheMachine() {
        #expect(ModelCatalog.default(fitting: Self.gigabytes(48)) == ModelCatalog.zImageTurbo8bit)
        #expect(ModelCatalog.default(fitting: Self.gigabytes(24)) == ModelCatalog.zImageTurbo8bit)
        #expect(ModelCatalog.default(fitting: Self.gigabytes(16)) == ModelCatalog.zImageTurbo4bit)
        // Nothing fits an 8 GB Mac, so it opens on the plain default rather than on nothing.
        #expect(ModelCatalog.default(fitting: Self.gigabytes(8)) == ModelCatalog.default)
        for gigabytes in [UInt64(8), 16, 24, 32, 48] {
            #expect(ModelCatalog.all.contains(ModelCatalog.default(fitting: Self.gigabytes(gigabytes))))
        }
    }

    @Test("every preset is aligned and inside the size bounds")
    func presetsAreValid() {
        for descriptor in ModelCatalog.all {
            let capabilities = descriptor.capabilities
            for preset in capabilities.sizePresets + [capabilities.defaultSize] {
                #expect(preset.aligned(to: capabilities.sizeAlignment) == preset)
                #expect(capabilities.sizeBounds.contains(preset.width))
                #expect(capabilities.sizeBounds.contains(preset.height))
            }
        }
    }

    @Test("the Turbo descriptor reads as family and variant")
    func fullName() {
        #expect(ModelCatalog.zImageTurbo8bit.fullName == "Z-Image Turbo · 8-bit")
        #expect(ModelCatalog.zImageTurbo8bit.backend == .zImage)
        #expect(ModelCatalog.zImageTurbo8bit.quantization.displayName == "8-bit")
    }
}

@Suite("ModelSource")
struct ModelSourceTests {
    @Test("the shipped model downloads from Hugging Face, a local directory never does")
    func requiresDownload() {
        #expect(ModelCatalog.zImageTurbo8bit.source.requiresDownload)
        #expect(!ModelSource.localDirectory(URL(filePath: "/tmp/x")).requiresDownload)
    }
}
