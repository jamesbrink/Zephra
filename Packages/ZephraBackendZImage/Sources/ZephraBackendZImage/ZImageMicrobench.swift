import Foundation
import MLX
import MLXFast

/// Standalone kernel timings for the shapes the Z-Image DiT actually runs, so a slow
/// generation can be attributed to a specific primitive rather than guessed at.
///
/// This is a diagnostic, not part of any production path: `ZephraBench --micro` is the
/// only caller.
public nonisolated enum ZImageMicrobench {
    /// The DiT's hidden size.
    private static let dim = 3840
    /// The DiT's head count and per-head width.
    private static let heads = 30
    private static let headDim = 128

    /// Times every primitive at the given sequence length, once per activation dtype, and
    /// prints one line each.
    public static func run(tokens: Int, iterations: Int = 10) {
        print("microbench: tokens=\(tokens) dim=\(dim) iterations=\(iterations)")
        let hidden = Int(Float(dim) / 3.0 * 8.0)
        for dtype in [DType.float32, DType.bfloat16] {
            let name = dtype == .float32 ? "f32 " : "bf16"
            print("  --- activations \(name) ---")
            matmulRow(label: "attn proj  \(name) dense [T,3840]x[3840,3840]", tokens: tokens, out: dim, dtype: dtype, iterations: iterations)
            quantRow(label: "attn proj  \(name) q8/32 [T,3840]x[3840,3840]", tokens: tokens, out: dim, bits: 8, groupSize: 32, dtype: dtype, iterations: iterations)
            quantRow(label: "attn proj  \(name) q8/64 [T,3840]x[3840,3840]", tokens: tokens, out: dim, bits: 8, groupSize: 64, dtype: dtype, iterations: iterations)
            quantRow(label: "attn proj  \(name) q4/64 [T,3840]x[3840,3840]", tokens: tokens, out: dim, bits: 4, groupSize: 64, dtype: dtype, iterations: iterations)
            quantRow(label: "ffn w1     \(name) q8/32 [T,3840]x[3840,\(hidden)]", tokens: tokens, out: hidden, bits: 8, groupSize: 32, dtype: dtype, iterations: iterations)
            sdpaRow(tokens: tokens, dtype: dtype, iterations: iterations)
            ropeRow(tokens: tokens, dtype: dtype, iterations: iterations)
        }
        rankRow(tokens: tokens, hidden: hidden)
        workingSetRow(tokens: tokens, hidden: hidden)
        print("note: a full step runs 32 layers x (4 attn proj + 3 ffn proj + 1 sdpa + 2 rope)")
    }


    /// Times a sweep over many distinct weight matrices, so the weights cannot stay in cache
    /// between calls the way a repeated single-matrix benchmark lets them. A real step streams
    /// about 7 GB of weights, and this is the only row that reproduces that.
    private static func workingSetRow(tokens: Int, hidden: Int) {
        // One byte per 8-bit weight, plus a 2-byte scale and bias per group of 32.
        let perMatrix = hidden * dim + 2 * (hidden * dim / 32) * 2
        let count = max(4, 7_000_000_000 / perMatrix)
        let x = MLXRandomNormal.make([tokens, dim], .bfloat16)
        var packed: [(MLXArray, MLXArray, MLXArray?)] = []
        packed.reserveCapacity(count)
        for _ in 0 ..< count {
            let w = MLXRandomNormal.make([hidden, dim], .bfloat16)
            let (wq, scales, biases) = MLX.quantized(w, groupSize: 32, bits: 8)
            MLX.eval(wq, scales)
            packed.append((wq, scales, biases))
        }
        let start = DispatchTime.now().uptimeNanoseconds
        for (wq, scales, biases) in packed {
            MLX.eval(
                MLX.quantizedMM(
                    x, wq, scales: scales, biases: biases,
                    transpose: true, groupSize: 32, bits: 8))
        }
        let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start) / 1e9
        report("ffn w1 x\(count) distinct weights", elapsed / Double(count))
        print(String(format: "    working set %.1f GB across %d matrices", Double(count * perMatrix) / 1e9, count))
    }


    /// The real model hands `Linear` a rank-3 `[1, tokens, dim]` activation, not the rank-2
    /// matrix every other row here uses. This checks whether MLX takes a slower batched path
    /// for the rank-3 shape.
    private static func rankRow(tokens: Int, hidden: Int) {
        let w = MLXRandomNormal.make([hidden, dim], .bfloat16)
        let (wq, scales, biases) = MLX.quantized(w, groupSize: 32, bits: 8)
        MLX.eval(wq, scales)
        for shape in [[tokens, dim], [1, tokens, dim]] {
            let x = MLXRandomNormal.make(shape, .bfloat16)
            report("ffn w1     bf16 q8/32 rank-\(shape.count) input", time(10) {
                MLX.quantizedMM(
                    x, wq, scales: scales, biases: biases,
                    transpose: true, groupSize: 32, bits: 8)
            })
        }
    }

    private static func matmulRow(label: String, tokens: Int, out: Int, dtype: DType, iterations: Int) {
        let x = MLXRandomNormal.make([tokens, dim], dtype)
        let w = MLXRandomNormal.make([dim, out], dtype)
        report(label, time(iterations) { MLX.matmul(x, w) })
    }

    private static func quantRow(label: String, tokens: Int, out: Int, bits: Int, groupSize: Int, dtype: DType, iterations: Int) {
        let x = MLXRandomNormal.make([tokens, dim], dtype)
        let w = MLXRandomNormal.make([out, dim], dtype)
        let (wq, scales, biases) = MLX.quantized(w, groupSize: groupSize, bits: bits)
        MLX.eval(wq, scales)
        report(label, time(iterations) {
            MLX.quantizedMM(x, wq, scales: scales, biases: biases, transpose: true, groupSize: groupSize, bits: bits)
        })
    }

    private static func sdpaRow(tokens: Int, dtype: DType, iterations: Int) {
        let q = MLXRandomNormal.make([1, heads, tokens, headDim], dtype)
        let k = MLXRandomNormal.make([1, heads, tokens, headDim], dtype)
        let v = MLXRandomNormal.make([1, heads, tokens, headDim], dtype)
        let scale = 1.0 / Float(headDim).squareRoot()
        let name = dtype == .float32 ? "f32 " : "bf16"
        // The model reaches attention through `.transposed(0, 2, 1, 3)` on a
        // [1, tokens, heads, headDim] projection, so its queries, keys and values are
        // non-contiguous views. This row is that shape; the next is a contiguous copy.
        if dtype == .bfloat16 {
            let qt = MLXRandomNormal.make([1, tokens, heads, headDim], dtype).transposed(0, 2, 1, 3)
            let kt = MLXRandomNormal.make([1, tokens, heads, headDim], dtype).transposed(0, 2, 1, 3)
            let vt = MLXRandomNormal.make([1, tokens, heads, headDim], dtype).transposed(0, 2, 1, 3)
            report("sdpa       bf16 transposed views", time(iterations) {
                MLXFast.scaledDotProductAttention(
                    queries: qt, keys: kt, values: vt, scale: scale, mask: nil)
            })
        }
        report("sdpa       \(name)       [1,30,T,128]", time(iterations) {
            MLXFast.scaledDotProductAttention(queries: q, keys: k, values: v, scale: scale, mask: nil)
        })
    }

    private static func ropeRow(tokens: Int, dtype: DType, iterations: Int) {
        let x = MLXRandomNormal.make([1, tokens, heads, headDim], dtype)
        let cos = MLXRandomNormal.make([1, tokens, 1, headDim / 2], dtype)
        let sin = MLXRandomNormal.make([1, tokens, 1, headDim / 2], dtype)
        let name = dtype == .float32 ? "f32 " : "bf16"
        report("rope stack \(name)       [1,T,30,128]", time(iterations) { stackedRotary(x, cos, sin) })
        report("rope split \(name)       [1,T,30,128]", time(iterations) { splitRotary(x, cos, sin) })
    }
}
