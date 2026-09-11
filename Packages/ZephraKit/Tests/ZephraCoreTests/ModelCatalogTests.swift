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

    @Test("Qwen-Image decodes exactly on a 36 GB Mac, streams on a 24 GB one, and not on 8")
    func qwenImageNeedsALargeMac() {
        // 30.9 GB of budget against a 30.4 GB peak: 36 GB is the smallest Mac sold that runs
        // this model with the exact decode, and it is a close thing.
        #expect(ModelCatalog.fit(ModelCatalog.qwenImage2512_4bit, physicalMemory: Self.gigabytes(36)) == .fits)
        #expect(ModelCatalog.fit(ModelCatalog.qwenImage2512_4bit, physicalMemory: Self.gigabytes(48)) == .fits)
        // A 24 GB Mac cannot hold the model tiled (26.1 GB) and can hold it streamed
        // (10.2 GB); so can a 16 GB one.
        #expect(ModelCatalog.fit(ModelCatalog.qwenImage2512_4bit, physicalMemory: Self.gigabytes(24)) == .fitsStreamed)
        #expect(ModelCatalog.fit(ModelCatalog.qwenImage2512_4bit, physicalMemory: Self.gigabytes(16)) == .fitsStreamed)
        let fit = ModelCatalog.fit(ModelCatalog.qwenImage2512_4bit, physicalMemory: Self.gigabytes(8))
        guard case .tight(let needed) = fit else {
            Issue.record("expected Qwen-Image not to fit on an 8 GB Mac even streamed")
            return
        }
        // The tiled peak itself: the GPU working set that would clear the budget.
        #expect(needed == ModelCatalog.qwenImage2512_4bit.tiledPeakBytes)
        #expect(needed == 26_070_000_000)
    }

    @Test("a 24 GB Mac runs the 4-bit model exactly and the 8-bit one only tiled")
    func twentyFourGigabytesNeedsTilingForEightBit() {
        let memory = Self.gigabytes(24)
        #expect(ModelCatalog.fit(ModelCatalog.zImageTurbo4bit, physicalMemory: memory) == .fits)
        // 23.5 GB untiled is over the 19.3 GB budget; 17.7 GB tiled is under it.
        #expect(ModelCatalog.fit(ModelCatalog.zImageTurbo8bit, physicalMemory: memory) == .fitsTiled)
        // Both Z-Image variants, both klein variants, Qwen-Image streamed, Wan 2.2 tiled
        // (12.4 GB under the 19.3 GB budget), and both LTX-2.5 entries streamed: the
        // measured 21.8 GB peak and the audio entry's larger one are over it.
        #expect(ModelCatalog.fitting(physicalMemory: memory).count == 8)
        #expect(ModelCatalog.fit(ModelCatalog.ltx2DistilledAudio4bit, physicalMemory: memory) == .fitsStreamed)
        #expect(ModelCatalog.fit(ModelCatalog.wan22TI2V5B4bit, physicalMemory: memory) == .fits)
        #expect(ModelCatalog.fit(ModelCatalog.qwenImage2512_4bit, physicalMemory: memory) == .fitsStreamed)
    }

    @Test("a Mac too small for a model is told how much memory it would take")
    func tightReportsWhatItWouldNeed() {
        let fit = ModelCatalog.fit(ModelCatalog.zImageTurbo8bit, physicalMemory: Self.gigabytes(8))
        guard case .tight(let needed) = fit else {
            Issue.record("expected the 8-bit model not to fit on an 8 GB Mac")
            return
        }
        // The tiled peak itself: the GPU working set the machine would need.
        #expect(needed == ModelCatalog.zImageTurbo8bit.tiledPeakBytes)
        let enough = MemoryBudget(physicalMemory: Self.gigabytes(48), gpuWorkingSet: UInt64(needed))
        #expect(ModelCatalog.fit(ModelCatalog.zImageTurbo8bit, budget: enough) == .fitsTiled)
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
                ModelCatalog.wan22TI2V5B4bit,
                ModelCatalog.ltx2Distilled4bit,
                ModelCatalog.ltx2DistilledAudio4bit,
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

    @Test("the Wan 2.2 entry is the quick clip family: three fixed steps, a first frame held exactly")
    func wanIsTheQuickClipFamily() {
        let descriptor = ModelCatalog.wan22TI2V5B4bit
        #expect(descriptor.backend == .wan)
        #expect(descriptor.isBuiltLocally && descriptor.isPublishedPrebuilt)
        #expect(descriptor.streamedPeakBytes > 0)
        #expect(descriptor.capabilities.producesVideo)
        #expect(descriptor.capabilities.frameBounds == 5...121)
        #expect(descriptor.capabilities.frameAlignment == 4)
        #expect(descriptor.capabilities.defaultFrames == 49)
        #expect(descriptor.capabilities.stepBounds == 3...3)
        #expect(descriptor.capabilities.guidanceBounds == 0...0)
        #expect(!descriptor.capabilities.supportsNegativePrompt)
        // A picture is the first frame and stays it: no strength, so no slider.
        #expect(descriptor.capabilities.supportsReferenceImage)
        #expect(!descriptor.capabilities.adjustsReferenceStrength)
        #expect(descriptor.maxPromptTokens == 512)
        guard case .huggingFace(let repoID, _, let patterns) = descriptor.source else {
            Issue.record("Wan 2.2 downloads from the hub")
            return
        }
        #expect(repoID == "FastVideo/FastWan2.2-TI2V-5B-FullAttn-Diffusers")
        #expect(patterns.contains("transformer/*") && patterns.contains("tokenizer/*"))
        #expect(!patterns.contains("assets/*") && !patterns.contains("examples/*"))
        // Listed before LTX-2.5, so Animate picks it.
        #expect(ModelCatalog.animator() == descriptor)
        for frames in [5, 49, 121] {
            var settings = GenerationSettings.defaults(for: descriptor)
            settings.frames = frames
            #expect(descriptor.capabilities.clamp(settings).frames == frames)
        }
        var odd = GenerationSettings.defaults(for: descriptor)
        odd.frames = 30
        #expect(descriptor.capabilities.clamp(odd).frames == 29)
    }

    @Test("the LTX-2.5 entry is video only, built from the ungated mirror pack, and makes clips")
    func ltx2IsVideoOnly() {
        let descriptor = ModelCatalog.ltx2Distilled4bit
        #expect(descriptor.backend == .ltx2)
        #expect(descriptor.isBuiltLocally && descriptor.isPublishedPrebuilt)
        #expect(descriptor.streamedPeakBytes > 0, "a 22B model streams on the Macs that cannot hold it")
        #expect(descriptor.capabilities.producesVideo)
        #expect(descriptor.capabilities.frameBounds == 9...121)
        #expect(descriptor.capabilities.defaultFrames == 49)
        #expect(descriptor.capabilities.stepBounds == 8...8)
        #expect(descriptor.capabilities.guidanceBounds == 0...0)
        // A picture is held as the clip's first frame, and the strength is inverted by the
        // backend: 0, the default, holds it exactly. So the range is offered from 0 and stops
        // short of 1, where the frame would not be held at all.
        #expect(descriptor.capabilities.supportsReferenceImage)
        #expect(descriptor.capabilities.referenceStrengthBounds == 0.0...0.9)
        #expect(descriptor.capabilities.defaultReferenceStrength == 0)
        #expect(descriptor.capabilities.adjustsReferenceStrength)
        #expect(descriptor.maxPromptTokens == 1024)
        guard case .huggingFace(let repoID, _, let patterns) = descriptor.source else {
            Issue.record("LTX-2.5 downloads from the hub")
            return
        }
        // Lightricks' repositories are gated; the catalog names the ungated redistribution.
        #expect(repoID == "mlx-community/ltx-2.5-mlx")
        #expect(patterns.contains("transformer-distilled.safetensors"))
        #expect(
            patterns.contains("vae_encoder.safetensors"),
            "the first frame a clip is held from is encoded by the autoencoder's own encoder")
        #expect(patterns.contains("spatial_upscaler_x2_v1_1.safetensors"), "the second stage doubles the latent with it")
        #expect(!patterns.contains { $0.contains("audio") || $0.contains("vocoder") || $0.contains("temporal") })
        #expect(patterns.contains("LICENSE.md"), "the LTX-2.x license travels with the weights")
        for frames in [9, 49, 121] {
            var settings = GenerationSettings.defaults(for: descriptor)
            settings.frames = frames
            #expect(descriptor.capabilities.clamp(settings).frames == frames)
        }
    }

    @Test("the Qwen-Image entry downloads a release and an adapter, and builds from both")
    func qwenImageIsBuiltFromAReleaseAndAnAdapter() throws {
        let descriptor = ModelCatalog.qwenImage2512_4bit
        #expect(descriptor.backend == .qwenImage)
        #expect(descriptor.source.requiresDownload)
        #expect(descriptor.isBuiltLocally)
        #expect(descriptor.downloadBytes == 57_700_000_000)
        #expect(descriptor.builtBytes == 21_600_000_000)
        #expect(descriptor.fullName == "Qwen-Image 2512 · 4-bit")
        guard case .huggingFace(let repoID, _, let patterns) = descriptor.source else {
            Issue.record("Qwen-Image downloads from the hub")
            return
        }
        #expect(repoID == "Qwen/Qwen-Image-2512")
        #expect(patterns.contains("transformer/*") && patterns.contains("tokenizer/*"))
        #expect(!patterns.contains("*"), "the README and .gitattributes are left out by omission")
        // The four-step distillation ships apart from the weights it distils, so choosing this
        // model costs both, and the picker's figure has to say so.
        #expect(descriptor.adapters.count == 1)
        let adapter = try #require(descriptor.adapters.first)
        #expect(adapter.repoID == "lightx2v/Qwen-Image-2512-Lightning")
        #expect(adapter.file == "Qwen-Image-2512-Lightning-4steps-V1.0-fp32.safetensors")
        #expect(descriptor.transferBytes == 57_700_000_000 + 1_698_951_104)
        // The adapter was distilled without classifier-free guidance, and it is merged into
        // these weights, so a guidance slider or a negative prompt would be a control nothing
        // answers to.
        #expect(descriptor.capabilities.defaultSteps == 4)
        #expect(descriptor.capabilities.guidanceBounds == 0...0)
        #expect(!descriptor.capabilities.supportsNegativePrompt)
        // The reference pipeline's max_sequence_length, which the request mapper passes on.
        #expect(descriptor.maxPromptTokens == 512)
    }

    @Test("the 4-bit Z-Image variant is packed here from the bf16 release, not from nothing")
    func fourBitIsBuiltFromTheRelease() {
        let descriptor = ModelCatalog.zImageTurbo4bit
        #expect(descriptor.source.requiresDownload)
        #expect(descriptor.isBuiltLocally)
        #expect(descriptor.builtBytes == 7_130_000_000)
        #expect(descriptor.quantization == .int4)
        #expect(descriptor.fullName == "Z-Image Turbo · 4-bit")
        #expect(descriptor.adapters.isEmpty)
        #expect(descriptor.isPublishedPrebuilt)
        #expect(descriptor.mirror == ModelCatalog.mirror)
        #expect(descriptor.transferBytes == descriptor.downloadBytes)
        #expect(descriptor.maxPromptTokens == ModelCatalog.zImageTurbo8bit.maxPromptTokens)
        #expect(descriptor.capabilities == ModelCatalog.zImageTurbo8bit.capabilities)
        guard case .huggingFace(let repoID, _, let patterns) = descriptor.source else {
            Issue.record("the 4-bit variant downloads its source from the hub")
            return
        }
        #expect(repoID == "Tongyi-MAI/Z-Image-Turbo")
        // `assets/` is 51 MB of sample pictures and a gallery PDF, left out by omission.
        #expect(!patterns.contains { $0.hasPrefix("assets") })
        #expect(!patterns.contains("*"))
        #expect(patterns.contains("*.safetensors") && patterns.contains("tokenizer/*"))
    }

    @Test("no catalog entry names an absolute directory any more")
    func nothingIsALocalDirectory() {
        for descriptor in ModelCatalog.all {
            #expect(
                descriptor.source.requiresDownload,
                "\(descriptor.id) would be unreachable on a Mac that never ran make quantize")
        }
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
        // Nothing fits an 8 GB Mac — no Zephra has been measured on one — so it opens on the
        // model that comes nearest to running rather than on the largest download of the six.
        #expect(ModelCatalog.default(fitting: Self.gigabytes(8)) == ModelCatalog.flux2Klein4bit)
        for gigabytes in [UInt64(8), 16, 24, 32, 48] {
            #expect(ModelCatalog.all.contains(ModelCatalog.default(fitting: Self.gigabytes(gigabytes))))
        }
    }

    @Test("a Mac nothing fits is offered the model needing the least, never the largest")
    func aMacNothingFitsIsOfferedTheLeanest() {
        let budget = Self.gigabytes(8)
        #expect(ModelCatalog.fitting(budget: MemoryBudget(physicalMemory: budget)).isEmpty)
        let offered = ModelCatalog.default(fitting: budget)
        for model in ModelCatalog.all {
            #expect(offered.leanestPeakBytes <= model.leanestPeakBytes)
        }
    }

    @Test("a family that streams is judged on its streamed peak, which is the smaller one")
    func leanestPeakTakesTheStreamedFigureWhenThereIsOne() {
        // Qwen-Image tiles to 26.1 GB and streams in 10.3; LTX-2.5 tiles to 23.4 and streams
        // in 10.0. Reading the tiled figure alone would rank both as heavier than they are.
        #expect(ModelCatalog.qwenImage2512_4bit.leanestPeakBytes
            == ModelCatalog.qwenImage2512_4bit.streamedPeakBytes)
        #expect(ModelCatalog.ltx2Distilled4bit.leanestPeakBytes
            == ModelCatalog.ltx2Distilled4bit.streamedPeakBytes)
        // klein cannot stream, so its tiled peak is the whole answer.
        #expect(ModelCatalog.flux2Klein4bit.streamedPeakBytes == 0)
        #expect(ModelCatalog.flux2Klein4bit.leanestPeakBytes
            == ModelCatalog.flux2Klein4bit.tiledPeakBytes)
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

extension ModelCatalogTests {
    @Test("every variant built locally is published on the one mirror, and nothing else is")
    func builtVariantsArePublished() {
        for descriptor in ModelCatalog.all {
            #expect(descriptor.isPublishedPrebuilt == descriptor.isBuiltLocally, "\(descriptor.id)")
            #expect((descriptor.mirror == nil) == !descriptor.isBuiltLocally, "\(descriptor.id)")
        }
        #expect(ModelCatalog.mirror.index.absoluteString == "https://zephra-assets.urandom.io/models/index.json")
        #expect(
            ModelCatalog.mirror.file("transformer/model.safetensors", of: "flux2-klein-4b-4bit").absoluteString
                == "https://zephra-assets.urandom.io/models/flux2-klein-4b-4bit/transformer/model.safetensors")
    }
}
