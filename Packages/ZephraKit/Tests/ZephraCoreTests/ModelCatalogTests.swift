import Testing

@testable import ZephraCore

@Suite("ModelCatalog")
struct ModelCatalogTests {
    @Test("an 8 GB Mac is offered nothing")
    func eightGigabytesFitsNothing() {
        #expect(ModelCatalog.fitting(physicalMemory: 8 * 1024 * 1024 * 1024).isEmpty)
    }

    @Test("a 16 GB Mac is not offered the 8-bit Turbo model, which needs ~13 GB resident")
    func sixteenGigabytesDoesNotFitTurbo() {
        let fitting = ModelCatalog.fitting(physicalMemory: 16 * 1024 * 1024 * 1024)
        #expect(!fitting.contains(ModelCatalog.zImageTurbo8bit))
    }

    @Test("a 32 GB Mac is offered the 8-bit Turbo model")
    func thirtyTwoGigabytesFitsTurbo() {
        let fitting = ModelCatalog.fitting(physicalMemory: 32 * 1024 * 1024 * 1024)
        #expect(fitting.contains(ModelCatalog.zImageTurbo8bit))
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
