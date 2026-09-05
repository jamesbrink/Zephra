import Foundation
import MLX
import MLXNN
import MLXRandom
import Testing
import ZephraMLX
import ZephraTestSupport

/// A pass that stops half way — Stop during a streamed step — must leave the stream able to
/// run the next pass right, and must not leave the stack resident.
extension LayerWeightStreamTests {
    struct Interrupted: Error {}

    @Test("a body that throws mid-pass leaves the next pass bit for bit right")
    func throwingMidPassLeavesTheNextPassRight() throws {
        let scratch = Scratch()
        let (directory, weights) = try Self.writeShards(into: scratch)
        let resident = LinearStack(count: Self.count, width: Self.width)
        try resident.update(parameters: ModuleParameters.unflattened(weights), verify: .all)
        let x = MLXRandom.normal([2, Self.width], key: MLXRandom.key(21))
        let expected = resident(x)
        MLX.eval(expected)

        let streamed = try Self.lazyStack(from: directory)
        let stream = try LayerWeightStream(
            layers: streamed.layers, keyPrefix: "layers", index: ShardIndex(directory: directory))
        var seen = 0
        #expect(throws: Interrupted.self) {
            try stream.run { layer in
                seen += 1
                if seen == 3 { throw Interrupted() }
                return [layer(x)]
            }
        }
        #expect(seen == 3, "the throw at layer 3 of 12 stopped the pass there")

        var y = x
        try stream.run { layer in
            y = layer(y)
            return [y]
        }
        MLX.eval(y)
        #expect(MLX.allClose(y, expected, rtol: 0, atol: 0).item(Bool.self))
    }

    @Test("after a throw no more than the window is resident")
    func afterAThrowOnlyTheWindowIsResident() throws {
        let scratch = Scratch()
        let (directory, _) = try Self.writeShards(into: scratch)
        let stack = try Self.lazyStack(from: directory)
        let stream = try LayerWeightStream(
            layers: stack.layers, keyPrefix: "layers", index: ShardIndex(directory: directory),
            depth: 1)
        let x = MLXRandom.normal([2, Self.width], key: MLXRandom.key(22))
        MLX.eval(x)
        // One whole pass first, so what earlier tests left behind is released before the
        // baseline is taken; see `onlyTheWindowIsResident`.
        var y = x
        try stream.run { layer in
            y = layer(y)
            return [y]
        }
        MLX.eval(y)
        Self.settle()
        let baseline = Memory.snapshot().activeMemory

        var seen = 0
        y = x
        #expect(throws: Interrupted.self) {
            try stream.run { layer in
                seen += 1
                if seen == 3 { throw Interrupted() }
                y = layer(y)
                return [y]
            }
        }
        MLX.eval(y)
        Self.settle()
        let after = Memory.snapshot().activeMemory
        // The layers read ahead of the throw, the one running, and the one before it may all
        // still be materialised; the nine layers after them must not be.
        let window = (stream.depth + 3) * Self.layerBytes
        let slack = 4 * x.nbytes + 1 << 20
        #expect(after - baseline <= window + slack, "\(after - baseline) over a \(window) window")
        #expect(after - baseline < Self.count * Self.layerBytes / 2, "most of the stack was resident")
    }
}
