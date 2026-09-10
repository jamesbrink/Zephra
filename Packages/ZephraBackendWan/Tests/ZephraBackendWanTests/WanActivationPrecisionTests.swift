import MLX
import Testing
import ZephraCore

@testable import ZephraBackendWan

@Suite("the Wan 2.2 stream's precision")
struct WanActivationPrecisionTests {
    @Test("bfloat16 by default, float32 only when asked for")
    func resolves() {
        var environment = InferenceEnvironment()
        #expect(WanActivationPrecision.resolve(environment: environment) == .bfloat16)
        environment.ditFloat32 = true
        #expect(WanActivationPrecision.resolve(environment: environment) == .float32)
        environment.ditFloat32 = false
        #expect(WanActivationPrecision.resolve(environment: environment) == .bfloat16)
    }
}
