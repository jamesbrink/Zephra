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

    @Test("a 16 GB Mac is offered the small models: klein exactly, the 4-bit Turbo model tiled")
    func sixteenGigabytesIsOfferedTheSmallModels() {
        let memory = Self.gigabytes(16)
        let fitting = ModelCatalog.fitting(physicalMemory: memory)
        #expect(!fitting.contains(ModelCatalog.zImageTurbo8bit))
        #expect(fitting.contains(ModelCatalog.zImageTurbo4bit))
        #expect(fitting.contains(ModelCatalog.flux2Klein4bit))
        #expect(ModelCatalog.fit(ModelCatalog.flux2Klein4bit, physicalMemory: memory) == .fits)
        // 12.0 GB tiled against a 13.7 GB budget; 17.8 GB untiled is well over it.
        #expect(ModelCatalog.fit(ModelCatalog.zImageTurbo4bit, physicalMemory: memory) == .fitsTiled)
        #expect(!ModelCatalog.fitsComfortably(ModelCatalog.zImageTurbo4bit, physicalMemory: memory))
    }

    @Test("a 32 GB Mac runs everything, but only Qwen-Image needs the tiled decode to do it")
    func thirtyTwoGigabytesFitsEverythingSomehow() {
        let memory = Self.gigabytes(32)
        #expect(ModelCatalog.fitting(physicalMemory: memory) == ModelCatalog.all)
        for model in [
            ModelCatalog.zImageTurbo8bit, ModelCatalog.zImageTurbo4bit,
            ModelCatalog.flux2Klein4bit, ModelCatalog.flux2Klein8bit,
        ] {
            #expect(ModelCatalog.fit(model, physicalMemory: memory) == .fits)
        }
        // 30.4 GB untiled is over the 27.5 GB budget; 26.1 GB tiled is under it. A 20-billion
        // parameter model was always going to be the one that needs the lever, which is why
        // this assertion is per model and not a loop over the catalog.
        #expect(
            ModelCatalog.fit(ModelCatalog.qwenImage2512_4bit, physicalMemory: memory)
                == .fitsTiled)
        #expect(!ModelCatalog.fitsComfortably(ModelCatalog.qwenImage2512_4bit, physicalMemory: memory))
    }

    @Test("Qwen-Image decodes exactly on a 36 GB Mac and not at all on a 24 GB one")
    func qwenImageNeedsALargeMac() {
        // 30.9 GB of budget against a 30.4 GB peak: 36 GB is the smallest Mac sold that runs
        // this model with the exact decode, and it is a close thing.
        #expect(ModelCatalog.fit(ModelCatalog.qwenImage2512_4bit, physicalMemory: Self.gigabytes(36)) == .fits)
        #expect(ModelCatalog.fit(ModelCatalog.qwenImage2512_4bit, physicalMemory: Self.gigabytes(48)) == .fits)
        let fit = ModelCatalog.fit(ModelCatalog.qwenImage2512_4bit, physicalMemory: Self.gigabytes(24))
        guard case .tight(let needed) = fit else {
            Issue.record("expected Qwen-Image not to fit on a 24 GB Mac")
            return
        }
        // The tiled peak over the working-set fraction: 26.07 GB of peak wants 32.6 GB of Mac.
        #expect(needed == 32_587_500_000)
    }

    @Test("a 24 GB Mac runs the 4-bit model exactly and the 8-bit one only tiled")
    func twentyFourGigabytesNeedsTilingForEightBit() {
        let memory = Self.gigabytes(24)
        #expect(ModelCatalog.fit(ModelCatalog.zImageTurbo4bit, physicalMemory: memory) == .fits)
        // 23.5 GB untiled is over the 19.3 GB budget; 17.7 GB tiled is under it.
        #expect(ModelCatalog.fit(ModelCatalog.zImageTurbo8bit, physicalMemory: memory) == .fitsTiled)
        // Both Z-Image variants and both klein variants; only Qwen-Image is left out.
        #expect(ModelCatalog.fitting(physicalMemory: memory).count == 4)
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

    @Test("the 8-bit Turbo model stays the default, and the list runs smallest machine first")
    func catalogOrder() {
        #expect(ModelCatalog.default == ModelCatalog.zImageTurbo8bit)
        #expect(
            ModelCatalog.all == [
                ModelCatalog.zImageTurbo8bit,
                ModelCatalog.flux2Klein4bit,
                ModelCatalog.flux2Klein8bit,
                ModelCatalog.zImageTurbo4bit,
                ModelCatalog.qwenImage2512_4bit,
            ],
            "the order is what a picker shows and what default(fitting:) walks, so a model that needs a larger Mac than the ones before it goes last; klein 4-bit sits before 8-bit so a 16 GB Mac lands on it by construction rather than by a measurement within a gigabyte of the budget"
        )
    }

    @Test("the klein entries are built here from one shared download, and one of them edits")
    func kleinIsBuiltFromItsOwnDownload() {
        for descriptor in [ModelCatalog.flux2Klein4bit, ModelCatalog.flux2Klein8bit] {
            #expect(descriptor.backend == .flux2)
            #expect(descriptor.source.requiresDownload)
            #expect(descriptor.isBuiltLocally)
            #expect(descriptor.builtBytes > 0)
            #expect(descriptor.downloadBytes == ModelCatalog.flux2KleinDownloadBytes)
            #expect(descriptor.source == ModelCatalog.flux2Klein4bit.source, "one download for both")
            #expect(descriptor.capabilities.supportsReferenceImage)
            #expect(descriptor.capabilities.defaultSteps == 4)
            #expect(descriptor.capabilities.guidanceBounds == 0...0)
            #expect(!descriptor.capabilities.supportsNegativePrompt)
            #expect(descriptor.maxPromptTokens == 512)
        }
        #expect(ModelCatalog.flux2Klein4bit.fullName == "FLUX.2 klein 4B · 4-bit")
        guard case .huggingFace(_, _, let patterns) = ModelCatalog.flux2Klein4bit.source else {
            Issue.record("klein downloads from the hub")
            return
        }
        // The root single-file checkpoint is 7.75 GB this loader never reads.
        #expect(!patterns.contains("*") && !patterns.contains("*.safetensors"))
        #expect(patterns.contains("vae/*") && patterns.contains("transformer/*"))
    }

    @Test("the Qwen-Image entry is a local build of a distilled model")
    func qwenImageIsALocalDistilledBuild() {
        let descriptor = ModelCatalog.qwenImage2512_4bit
        #expect(descriptor.backend == .qwenImage)
        #expect(!descriptor.source.requiresDownload)
        #expect(descriptor.downloadBytes == 0)
        #expect(descriptor.builtBytes == 21_600_000_000)
        #expect(!descriptor.isBuiltLocally, "built by make, not by the app: there is no download")
        #expect(descriptor.fullName == "Qwen-Image 2512 · 4-bit")
        #expect(
            descriptor.source
                == .localDirectory(
                    ModelCatalog.localModelsDirectory.appending(path: "qwen-image-2512-4bit")))
        // The four-step Lightning adapter is merged into these weights, and it was distilled
        // without classifier-free guidance. Offering a guidance slider or a negative prompt
        // would show a control the merged weights cannot answer to.
        #expect(descriptor.capabilities.defaultSteps == 4)
        #expect(descriptor.capabilities.guidanceBounds == 0...0)
        #expect(!descriptor.capabilities.supportsNegativePrompt)
        // The reference pipeline's max_sequence_length, which the request mapper passes on.
        #expect(descriptor.maxPromptTokens == 512)
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
        #expect(ModelCatalog.default(fitting: Self.gigabytes(16)) == ModelCatalog.flux2Klein4bit)
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
