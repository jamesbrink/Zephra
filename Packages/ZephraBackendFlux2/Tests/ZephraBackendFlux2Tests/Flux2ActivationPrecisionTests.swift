import MLX
import Testing

@testable import ZephraBackendFlux2

@Suite("The stream's dtype follows the device unless the environment says otherwise")
struct Flux2ActivationPrecisionTests {
    @Test("bfloat16 off an M5, float32 on one")
    func gatesOnTheDevice() {
        #expect(Flux2ActivationPrecision.resolve(environment: [:], isM5Class: false) == .bfloat16)
        #expect(Flux2ActivationPrecision.resolve(environment: [:], isM5Class: true) == .float32)
    }

    @Test("ZEPHRA_DIT_DTYPE overrides the gate either way")
    func environmentWins() {
        let f32 = ["ZEPHRA_DIT_DTYPE": "f32"]
        let bf16 = ["ZEPHRA_DIT_DTYPE": "bf16"]
        #expect(Flux2ActivationPrecision.resolve(environment: f32, isM5Class: false) == .float32)
        #expect(Flux2ActivationPrecision.resolve(environment: bf16, isM5Class: true) == .bfloat16)
    }

    @Test("a value that names neither dtype is ignored rather than taken for one")
    func unknownValueFallsThrough() {
        let other = ["ZEPHRA_DIT_DTYPE": "fp16"]
        #expect(Flux2ActivationPrecision.resolve(environment: other, isM5Class: false) == .bfloat16)
        #expect(Flux2ActivationPrecision.resolve(environment: other, isM5Class: true) == .float32)
    }
}
