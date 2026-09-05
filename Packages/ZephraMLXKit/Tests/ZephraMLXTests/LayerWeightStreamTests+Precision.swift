import Foundation
import MLX
import MLXNN
import MLXRandom
import Testing
import ZephraMLX
import ZephraTestSupport

/// What dtype a streamed layer's weights come back in.
///
/// A loader that brings float32 parameters down to the activation dtype does so before the
/// stream is attached, the way the kits' `castFloatParameters` do. The stream must then hand
/// back that dtype on every pass, and not the shards' own float32 from the second pass on,
/// which is what widened Qwen-Image's whole stream after its first block.
extension LayerWeightStreamTests {
    @Test("a slot cast at load keeps its dtype on every later pass")
    func castSurvivesStreaming() throws {
        let scratch = Scratch()
        let (directory, weights) = try Self.writeShards(into: scratch)
        let resident = LinearStack(count: Self.count, width: Self.width)
        try resident.update(
            parameters: ModuleParameters.unflattened(weights.mapValues { $0.asType(.bfloat16) }),
            verify: .all)
        let x = MLXRandom.normal([2, Self.width], key: MLXRandom.key(99)).asType(.bfloat16)
        let expected = resident(x)
        MLX.eval(expected)
        #expect(expected.dtype == .bfloat16)

        let streamed = try Self.lazyStack(from: directory)
        streamed.update(parameters: streamed.parameters().mapValues { $0.asType(.bfloat16) })
        let stream = try LayerWeightStream(
            layers: streamed.layers, keyPrefix: "layers", index: ShardIndex(directory: directory))
        for pass in 0..<2 {
            var y = x
            try stream.run { layer in
                y = layer(y)
                return [y]
            }
            MLX.eval(y)
            #expect(y.dtype == .bfloat16, "pass \(pass) widened the stream")
            #expect(MLX.allClose(y, expected, rtol: 0, atol: 0).item(Bool.self), "pass \(pass)")
            let dtypes = Set(streamed.parameters().flattened().map(\.1.dtype))
            #expect(dtypes == [.bfloat16], "after pass \(pass) the tree holds \(dtypes)")
        }
    }
}
