import MLX
import Testing
import ZephraMLX

@Suite("Runtime shutdown synchronization")
struct MLXRuntimeTests {
    @Test("asynchronously submitted GPU work can settle before runtime teardown")
    func drainsSubmittedWork() {
        let value = MLXArray.ones([32, 32])
        let result = matmul(value, value)
        asyncEval(result)
        MLXRuntime.synchronize()
        #expect(result[0, 0].item(Float.self) == 32)
        MLXRuntime.synchronize()
    }
}
