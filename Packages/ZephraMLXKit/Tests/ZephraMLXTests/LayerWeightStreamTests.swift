import Foundation
import MLX
import MLXNN
import MLXRandom
import Testing
import ZephraMLX
import ZephraTestSupport

/// A doll's-house transformer: a stack of identical linear layers under one key.
final class LinearStack: Module {
    @ModuleInfo(key: "layers") var layers: [Linear]

    init(count: Int, width: Int) {
        _layers.wrappedValue = (0..<count).map { _ in Linear(width, width, bias: true) }
    }

    func callAsFunction(_ x: MLXArray) -> MLXArray {
        layers.reduce(x) { $1($0) }
    }
}

// `.serialized` because `WeightStreamMeter` is one process-wide slot and three tests in here
// run a pass that writes it. Swift Testing runs a suite's tests in parallel by default, so
// "the meter holds the pass this stream just recorded" was only ever true by luck: another
// test's pass would land in the meter in between, and the assertion failed on `seconds` while
// `bytes` matched, since every stack in this file streams the same number of bytes. The stream
// records one value into both its own `lastPass` and the meter, so with the tests serialized
// the two really are the same reading.
@Suite("Streaming a layer stack from its shards", .serialized)
struct LayerWeightStreamTests {
    static let width = 1024
    static let count = 12
    /// One layer: a float32 weight of width squared and a bias of width.
    static let layerBytes = (width * width + width) * 4
    /// The layer whose weight is in the first shard and whose bias is in the second.
    static let straddling = 6

    /// Writes twelve layers over two shards, with one layer's weight in the first and its
    /// bias in the second, and hands back every tensor evaluated.
    static func writeShards(into scratch: Scratch) throws -> (directory: URL, weights: [String: MLXArray]) {
        let directory = try scratch.make("stack", isDirectory: true)
        var all: [String: MLXArray] = [:]
        for layer in 0..<count {
            let key = MLXRandom.key(UInt64(layer))
            all["layers.\(layer).weight"] = MLXRandom.normal([width, width], key: key) * 0.02
            all["layers.\(layer).bias"] = MLXRandom.normal([width], key: key) * 0.01
        }
        MLX.eval(all.values)
        let first = all.filter { name, _ in
            let layer = Int(name.split(separator: ".")[1])!
            return layer < straddling || (layer == straddling && name.hasSuffix("weight"))
        }
        let second = all.filter { first[$0.key] == nil }
        try MLX.save(arrays: first, url: directory.appending(path: "model-00001-of-00002.safetensors"))
        try MLX.save(arrays: second, url: directory.appending(path: "model-00002-of-00002.safetensors"))
        return (directory, all)
    }

    /// Waits for the buffers of completed command buffers to be handed back: Metal runs a
    /// completion handler on its own thread a moment after `eval` returns, so a reading taken
    /// straight after one still counts what is about to be freed.
    static func settle() {
        var last = -1
        var steady = 0
        for _ in 0..<200 where steady < 5 {
            Memory.clearCache()
            let active = Memory.snapshot().activeMemory
            steady = active == last ? steady + 1 : 0
            last = active
            Thread.sleep(forTimeInterval: 0.01)
        }
    }

    /// A stack filled from the shards and left lazy, the way the loader leaves one.
    static func lazyStack(from directory: URL) throws -> LinearStack {
        let stack = LinearStack(count: count, width: width)
        var loaded: [String: MLXArray] = [:]
        for shard in try ShardIndex(directory: directory).shards {
            loaded.merge(try MLX.loadArrays(url: shard)) { first, _ in first }
        }
        try stack.update(parameters: ModuleParameters.unflattened(loaded), verify: .all)
        return stack
    }

    @Test("the index knows every tensor's shard and size without reading one")
    func indexKnowsWhereEverythingIs() throws {
        let scratch = Scratch()
        defer { withExtendedLifetime(scratch) {} }  // the shards are read lazily, at eval, not at load
        let (directory, weights) = try Self.writeShards(into: scratch)
        let index = try ShardIndex(directory: directory)
        #expect(index.shards.count == 2)
        #expect(index.entries.count == weights.count)
        let straddling = Self.straddling
        #expect(index.entries["layers.\(straddling).weight"]?.shard.lastPathComponent == "model-00001-of-00002.safetensors")
        #expect(index.entries["layers.\(straddling).bias"]?.shard.lastPathComponent == "model-00002-of-00002.safetensors")
        #expect(index.bytes(ofKeys: ["layers.0.weight", "layers.0.bias"]) == Self.layerBytes)
        #expect(index.shards(holding: ["layers.0.weight"]).count == 1)
        #expect(index.shards(holding: ["layers.\(straddling).weight", "layers.\(straddling).bias"]).count == 2)
    }

    @Test("a streamed pass is the resident pass bit for bit, twice over")
    func streamedMatchesResident() throws {
        let scratch = Scratch()
        defer { withExtendedLifetime(scratch) {} }  // the shards are read lazily, at eval, not at load
        let (directory, weights) = try Self.writeShards(into: scratch)
        let resident = LinearStack(count: Self.count, width: Self.width)
        try resident.update(parameters: ModuleParameters.unflattened(weights), verify: .all)
        let x = MLXRandom.normal([2, Self.width], key: MLXRandom.key(99))
        let expected = resident(x)
        MLX.eval(expected)

        let streamed = try Self.lazyStack(from: directory)
        let stream = try LayerWeightStream(
            layers: streamed.layers, keyPrefix: "layers", index: ShardIndex(directory: directory))
        #expect(stream.bytesPerPass == Self.count * Self.layerBytes)
        for pass in 0..<2 {
            var y = x
            try stream.run { layer in
                y = layer(y)
                return [y]
            }
            MLX.eval(y)
            #expect(MLX.allClose(y, expected, rtol: 0, atol: 0).item(Bool.self), "pass \(pass)")
            #expect(stream.lastPass?.bytes == Self.count * Self.layerBytes)
            #expect((stream.lastPass?.seconds ?? 0) > 0)
        }
        #expect(WeightStreamMeter.lastPass == stream.lastPass)
    }

    @Test("only a window of layers is ever materialised")
    func onlyTheWindowIsResident() throws {
        let scratch = Scratch()
        defer { withExtendedLifetime(scratch) {} }  // the shards are read lazily, at eval, not at load
        let (directory, _) = try Self.writeShards(into: scratch)
        let stack = try Self.lazyStack(from: directory)
        let stream = try LayerWeightStream(
            layers: stack.layers, keyPrefix: "layers", index: ShardIndex(directory: directory),
            depth: 1)
        let x = MLXRandom.normal([2, Self.width], key: MLXRandom.key(7))
        MLX.eval(x)
        // One pass first, unmeasured: what earlier tests in this process left behind is
        // released while it runs, and a baseline taken before that would drift under the
        // measurement.
        var y = x
        try stream.run { layer in
            y = layer(y)
            return [y]
        }
        MLX.eval(y)
        Self.settle()
        let baseline = Memory.snapshot().activeMemory
        var high = 0
        y = x
        try stream.run { layer in
            y = layer(y)
            // Sampled after the layer's graph is built and before it is committed, which is
            // when this layer, the one read ahead, and the one just released can all be live.
            high = max(high, Memory.snapshot().activeMemory)
            return [y]
        }
        MLX.eval(y)
        Self.settle()
        let after = Memory.snapshot().activeMemory
        // The window is depth + 1 layers, the one before the running layer may still be live
        // at the sample (its command buffers are waited for only after this layer's are
        // committed), and one more may be done but not yet handed back, since Metal frees on
        // its own thread a moment after the wait returns. Twelve layers against four is the
        // margin that says the stack was not read whole.
        let window = (stream.depth + 3) * Self.layerBytes
        let slack = 4 * x.nbytes + 1 << 20
        #expect(high - baseline <= window + slack, "\(high - baseline) over a \(window) window")
        #expect(high - baseline < Self.count * Self.layerBytes / 2, "most of the stack was resident")
        // Once the pass is over every layer holds a lazy node and every command buffer has
        // completed, so nothing of the stack is live any more.
        #expect(after - baseline < 2 * Self.layerBytes, "\(after - baseline) still live after the pass")
    }

    @Test("a tensor the shards do not carry fails at set-up, not mid-pass")
    func missingTensorFailsEarly() throws {
        let scratch = Scratch()
        defer { withExtendedLifetime(scratch) {} }  // the shards are read lazily, at eval, not at load
        let (directory, _) = try Self.writeShards(into: scratch)
        let tooTall = LinearStack(count: Self.count + 1, width: Self.width)
        #expect {
            _ = try LayerWeightStream(
                layers: tooTall.layers, keyPrefix: "layers", index: ShardIndex(directory: directory))
        } throws: { error in
            // Whichever of the extra layer's two tensors is looked up first.
            guard case .missingTensor(let name) = error as? LayerWeightStreamError else { return false }
            return name.hasPrefix("layers.\(Self.count).")
        }
    }

    @Test("a module path is looked up under the checkpoint's own name")
    func checkpointNamesAreRenamed() throws {
        let scratch = Scratch()
        defer { withExtendedLifetime(scratch) {} }  // the shards are read lazily, at eval, not at load
        let (directory, _) = try Self.writeShards(into: scratch)
        let stack = try Self.lazyStack(from: directory)
        let stream = try LayerWeightStream(
            layers: stack.layers, keyPrefix: "blocks", index: ShardIndex(directory: directory),
            checkpointName: { $0.replacingOccurrences(of: "blocks.", with: "layers.") })
        #expect(stream.bytesPerPass == Self.count * Self.layerBytes)
    }
}
