import Foundation
import MLX
import MLXRandom
import Testing
import ZephraMLX

/// The one rotation both ports share, in the two compute dtypes they ask for.
@Suite("Rotating channel pairs by a rotary table")
struct RotaryFrequenciesTests {
    /// A doll's-house table: five positions, four pairs, angles that are not all zero.
    private static func table() -> RotaryFrequencies {
        let angles = MLXArray((0..<20).map { Float($0) * 0.3 }, [5, 4])
        return RotaryFrequencies(cos: MLX.cos(angles), sin: MLX.sin(angles))
    }

    private static func pairMagnitudes(_ value: MLXArray) -> MLXArray {
        let pairs = value.asType(.float32).reshaped([2, 5, 3, 4, 2])
        return MLX.sqrt(MLX.sum(pairs * pairs, axis: -1))
    }

    @Test("rotating in either dtype keeps every pair's magnitude and the input's dtype")
    func rotationPreservesMagnitudeAndDtype() {
        let table = Self.table()
        let x = MLXRandom.normal([2, 5, 3, 8], key: MLXRandom.key(1))
        for dtype in [DType.float32, DType.bfloat16] {
            let input = x.asType(dtype)
            for compute in [DType.float32, dtype] {
                let rotated = table.rotate(input, computeDType: compute)
                #expect(rotated.dtype == dtype, "the result is the input's dtype, not the compute's")
                #expect(rotated.shape == x.shape)
                let difference = MLX.max(
                    MLX.abs(Self.pairMagnitudes(rotated) - Self.pairMagnitudes(input))
                ).item(Float.self)
                // bfloat16 has about three significant digits.
                #expect(difference < (dtype == .float32 ? 1e-5 : 3e-2))
            }
        }
    }

    @Test("a zero angle is the identity in both compute dtypes")
    func zeroAngleIsIdentity() {
        let identity = RotaryFrequencies(cos: MLXArray.ones([5, 4]), sin: MLXArray.zeros([5, 4]))
        let x = MLXRandom.normal([2, 5, 3, 8], key: MLXRandom.key(2))
        #expect(MLX.allClose(identity.rotate(x, computeDType: .float32), x, atol: 1e-6).item(Bool.self))
        let half = x.asType(.bfloat16)
        #expect(MLX.allClose(identity.rotate(half, computeDType: .bfloat16), half, atol: 0).item(Bool.self))
    }

    @Test("a float32 rotation of a bfloat16 input is the float32 answer rounded once")
    func float32ComputeIsTheReferenceRoundedOnce() {
        let table = Self.table()
        let x = MLXRandom.normal([2, 5, 3, 8], key: MLXRandom.key(3)).asType(.bfloat16)
        let exact = table.rotate(x.asType(.float32), computeDType: .float32)
        let viaFloat32 = table.rotate(x, computeDType: .float32)
        let viaBfloat16 = table.rotate(x, computeDType: .bfloat16)
        #expect(MLX.allClose(viaFloat32, exact.asType(.bfloat16), atol: 0).item(Bool.self),
                "rotating in float32 and casting once is exactly the reference rounded")
        // Rotating in bfloat16 rounds at every multiply, so it is close but not the same path.
        let gap = MLX.max(MLX.abs(viaBfloat16.asType(.float32) - exact)).item(Float.self)
        #expect(gap < 5e-2)
    }
}
