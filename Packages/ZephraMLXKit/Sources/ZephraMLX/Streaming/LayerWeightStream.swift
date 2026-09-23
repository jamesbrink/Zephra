import Foundation
import MLX
import MLXNN
import ZephraCore

/// Runs a stack of identical layers with only a few of their weights in memory at once.
///
/// The weights of a layer are read from the shards `depth` layers before they are needed, on
/// the CPU stream while the GPU is still busy with the layers before, and dropped as soon as
/// the layer's work is committed. So a transformer of sixty blocks holds three, and a model
/// larger than the GPU's working set runs, at the cost of reading the whole of it from disk on
/// every pass.
///
/// The mechanism is in `run`, and its order is load-bearing. A layer's outputs are committed
/// with `asyncEval` as soon as its graph is built, and per layer at all, because an
/// unevaluated graph holds every layer's weights as inputs, which would read most of the
/// model before any of it ran. Then the layer before it is waited for, and only then is the
/// next read queued: MLX allocates a tensor's buffer when its read is queued, not when the
/// bytes arrive, so a loop that queued reads freely would hold as many layers as MLX's task
/// limit let it run ahead — five or six in a small model — rather than the window asked for.
/// Waiting on the layer before, not the one just committed, leaves the GPU a layer of work
/// in hand while the wait happens. A layer is released by giving each of its parameter arrays
/// a fresh, unevaluated node from the next pass's shards: the buffers it held live exactly
/// until its command buffers complete, and nothing has to remember a placeholder.
///
/// What is handed back is in the dtype the tree held at capture, not the dtype on disk. A
/// loader that casts float32 scales down to the activation dtype does so before the stream is
/// attached, and the stream keeps that cast on every later pass; without it the second pass
/// would read the raw float32 scales and widen the whole stream after the first layer.
public final class LayerWeightStream<Layer: Module> {
    /// One parameter of one layer: the very array the forward pass reads, the checkpoint name
    /// it is filled from, the dtype the tree holds it in, and what it costs to read.
    struct Slot {
        let checkpointKey: String
        let array: MLXArray
        let dtype: DType
        let bytes: Int
    }

    /// How many layers are read ahead of the one running. Together with the one running and
    /// the one just finished, whose buffers go back as its command buffers complete, at most
    /// `depth + 2` layers are ever in memory.
    public var depth: Int
    /// The last pass this stream ran; nil before the first.
    public private(set) var lastPass: WeightStreamReading?
    /// Bytes one pass reads: every layer's weights, once.
    public let bytesPerPass: Int

    private let layers: [Layer]
    let slots: [[Slot]]
    private let shards: [URL]

    /// Prepares `layers` to stream.
    ///
    /// Call it after the layers were filled from the shards and before anything evaluates
    /// them: the arrays captured here are the ones the loader put in the tree, still lazy,
    /// and the first pass reads them the way every later pass does.
    ///
    /// - Parameters:
    ///   - layers: The stack, in the order it runs.
    ///   - keyPrefix: The module path of the stack in its tree, such as `transformer_blocks`.
    ///   - index: Where every tensor of the component is.
    ///   - depth: Layers read ahead. Two holds three layers at once.
    ///   - checkpointName: The checkpoint's name for a module path, where the two differ.
    /// - Throws: `LayerWeightStreamError.missingTensor` when a layer wants a tensor the shards
    ///   do not carry, so a variant that does not match the tree fails at load and not mid-step.
    public init(
        layers: [Layer],
        keyPrefix: String,
        index: ShardIndex,
        depth: Int = 2,
        checkpointName: (String) -> String = { $0 }
    ) throws {
        var slots: [[Slot]] = []
        for (position, layer) in layers.enumerated() {
            var own: [Slot] = []
            for (key, array) in layer.parameters().flattened() {
                let name = checkpointName("\(keyPrefix).\(position).\(key)")
                guard let entry = index.entries[name] else {
                    throw LayerWeightStreamError.missingTensor(name)
                }
                own.append(.init(checkpointKey: name, array: array, dtype: array.dtype, bytes: entry.bytes))
            }
            slots.append(own)
        }
        self.layers = layers
        self.slots = slots
        self.depth = max(0, depth)
        self.bytesPerPass = slots.reduce(0) { $0 + $1.reduce(0) { $0 + $1.bytes } }
        self.shards = index.shards(holding: slots.joined().map(\.checkpointKey))
    }

    /// One pass over the stack. `body` runs one layer's own work and returns the arrays that
    /// carry its result into the next layer, which are what gets committed before the layer
    /// is released.
    public func run(_ body: (Layer) throws -> [MLXArray]) throws {
        let clock = ContinuousClock()
        let started = clock.now
        var next = try openPass()
        let count = layers.count
        for ahead in 0..<min(depth, count) {
            prefetch(ahead)
        }
        var previous: [MLXArray] = []
        var released = 0
        do {
            for position in 0..<count {
                let carry = try body(layers[position])
                MLX.asyncEval(carry)
                // The layer before this one has had a whole layer's work to finish in; waiting
                // for it here is what bounds the window, and the GPU still holds this layer.
                if !previous.isEmpty { MLX.eval(previous) }
                previous = carry
                if position + depth < count {
                    prefetch(position + depth)
                }
                try release(position, from: &next)
                released = position + 1
            }
        } catch {
            recover(from: released, using: &next)
            throw error
        }
        let elapsed = started.duration(to: clock.now).components
        let reading = WeightStreamReading(
            bytes: bytesPerPass, seconds: Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18)
        lastPass = reading
        WeightStreamMeter.record(reading)
    }

    /// Fresh, unevaluated nodes for every tensor in the shards the stack uses: what the layers
    /// are handed as they are released, so what the next pass reads.
    private func openPass() throws -> [String: MLXArray] {
        var all: [String: MLXArray] = [:]
        for shard in shards {
            all.merge(try MLX.loadArrays(url: shard)) { first, _ in first }
        }
        return all
    }

    /// Starts reading a layer's weights on the CPU stream.
    private func prefetch(_ position: Int) {
        MLX.asyncEval(slots[position].map(\.array))
    }

    /// Points a layer's arrays at the next pass's nodes, dropping what they held once the work
    /// committed against it completes. A node is cast back to the dtype the slot was captured
    /// in: a lazy cast over a lazy read, evaluated by the next prefetch.
    private func release(_ position: Int, from next: inout [String: MLXArray]) throws {
        for slot in slots[position] {
            guard let fresh = next.removeValue(forKey: slot.checkpointKey) else {
                throw LayerWeightStreamError.tensorGone(slot.checkpointKey)
            }
            slot.array._updateInternal(fresh.dtype == slot.dtype ? fresh : fresh.asType(slot.dtype))
        }
    }
}
