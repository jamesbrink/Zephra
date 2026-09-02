import Foundation
import Testing

@testable import ZephraCore

@Suite("ModelCatalog")
struct ModelCatalogTests {
    @Test("an 8 GB Mac is offered nothing")
    func eightGigabytesFitsNothing() {
        #expect(ModelCatalog.fitting(physicalMemory: 8 * 1024 * 1024 * 1024).isEmpty)
    }

    @Test("a 16 GB Mac is offered the 4-bit Turbo model but not the 8-bit one")
    func sixteenGigabytesFitsOnlyFourBit() {
        let fitting = ModelCatalog.fitting(physicalMemory: 16 * 1024 * 1024 * 1024)
        #expect(!fitting.contains(ModelCatalog.zImageTurbo8bit))
        #expect(fitting.contains(ModelCatalog.zImageTurbo4bit))
    }

    @Test("a 32 GB Mac is offered both Turbo variants")
    func thirtyTwoGigabytesFitsBoth() {
        let fitting = ModelCatalog.fitting(physicalMemory: 32 * 1024 * 1024 * 1024)
        #expect(fitting.contains(ModelCatalog.zImageTurbo8bit))
        #expect(fitting.contains(ModelCatalog.zImageTurbo4bit))
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
