import MLX
import Testing
import ZephraCore

@testable import ZephraBackendLTX2

@Suite("the LTX-2.5 stream's precision")
struct LTX2ActivationPrecisionTests {
    @Test("bfloat16 by default, float32 only when asked for")
    func resolves() {
        var environment = InferenceEnvironment()
        #expect(LTX2ActivationPrecision.resolve(environment: environment) == .bfloat16)
        environment.ditFloat32 = true
        #expect(LTX2ActivationPrecision.resolve(environment: environment) == .float32)
        environment.ditFloat32 = false
        #expect(LTX2ActivationPrecision.resolve(environment: environment) == .bfloat16)
    }
}
