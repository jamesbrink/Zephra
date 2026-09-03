import Foundation
import Testing
import ZephraCore

@testable import ZephraBackendFlux2

@Suite("Settings become a klein request only after the model's limits are applied")
struct Flux2RequestMapperTests {
    private let descriptor = ModelCatalog.flux2Klein4bit

    @Test("size is aligned and bounded, steps are bounded, and the reference rides along")
    func clampsAndCarries() {
        let picture = Data([1, 2, 3])
        let settings = GenerationSettings(
            prompt: "a red door", size: ImageSize(width: 1030, height: 2000), steps: 40,
            guidance: 3, seed: 7, referenceImage: picture)
        let request = Flux2RequestMapper.request(for: settings, descriptor: descriptor)
        #expect(request.width == 1024)
        #expect(request.height == 1536)
        #expect(request.steps == 8)
        #expect(request.seed == 7)
        #expect(request.maxPromptTokens == 512)
        #expect(request.referenceImage == picture)
    }

    @Test("a model that cannot read a reference drops it before the request is built")
    func dropsReferenceWhereUnsupported() {
        let settings = GenerationSettings(
            prompt: "x", size: ImageSize(width: 1024, height: 1024), steps: 4, guidance: 0,
            seed: 1, referenceImage: Data([9]))
        let request = Flux2RequestMapper.request(for: settings, descriptor: ModelCatalog.zImageTurbo4bit)
        #expect(request.referenceImage == nil)
    }
}
