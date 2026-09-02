import MLX

/// Bare bf16 noise, kept separate so the microbench does not depend on the pipeline's
/// random-key plumbing.
enum MLXRandomNormal {
    static func make(_ shape: [Int], _ dtype: DType = .bfloat16) -> MLXArray {
        let count = shape.reduce(1, *)
        var values = [Float](repeating: 0, count: count)
        var state: UInt64 = 0x2545_F491_4F6C_DD1D
        for index in 0 ..< count {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            values[index] = Float(Int32(truncatingIfNeeded: state >> 32)) / Float(Int32.max) * 0.1
        }
        let array = MLXArray(values, shape).asType(dtype)
        MLX.eval(array)
        return array
    }
}
