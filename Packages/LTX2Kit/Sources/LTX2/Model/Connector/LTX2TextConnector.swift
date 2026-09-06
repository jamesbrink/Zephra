import Foundation
import MLX
import MLXNN

/// The 1-D transformer between the text features and the DiT: eight gated blocks over the
/// prompt's 1024 positions, with the padding replaced by learned registers.
///
/// Before the first block the real tokens are moved to the front in their original order and
/// every position after them is filled from a bank of 128 registers, position `p` taking
/// register `p mod 128`. Nothing is masked after that: the registers are real tokens as far as
/// attention is concerned, and the output is 1024 positions the DiT attends to in full. The
/// stream's width is a parameter so an audio connector, 2048 wide, can be a second instance.
final class LTX2TextConnector: Module {
    @ParameterInfo(key: "learnable_registers") var registers: MLXArray
    @ModuleInfo(key: "transformer_1d_blocks") var blocks: [LTX2ConnectorBlock]

    private let rotary: LTX2RotaryEmbedding
    private let eps: Float

    /// The checkpoint's prefix for this module's paths.
    static let checkpointPrefix = LTX2ConnectorWeights.connectorPrefix
    /// Blocks in LTX-2.5's connector (`connector_num_layers` in its embedded config).
    static let defaultLayers = 8

    /// - Parameters:
    ///   - dim: The stream's width, 4096 for video.
    ///   - heads: Attention heads per block, 32.
    ///   - layers: Blocks, 8.
    ///   - registerCount: Registers in the bank, 128; the sequence length must divide by it.
    ///   - maxPosition: The nominal length the rotary embedding measures positions against.
    init(
        dim: Int, heads: Int, layers: Int, registerCount: Int = 128, maxPosition: Int = 4096,
        eps: Float = 1e-6
    ) {
        self.eps = eps
        // The DiT's embedding over one axis: positions are fractions of `maxPosition`, mapped
        // to -1...1, so a token's angle depends on where it sits in that span.
        rotary = LTX2RotaryEmbedding(
            heads: heads, headDim: dim / heads, maxPositions: [Double(maxPosition)], theta: 10_000)
        _registers.wrappedValue = MLXArray.zeros([registerCount, dim])
        _blocks.wrappedValue = (0..<layers).map { _ in LTX2ConnectorBlock(dim: dim, heads: heads, eps: eps) }
    }

    /// The conditioning for the DiT, `[batch, length, dim]`, from `features` of the same shape
    /// under `padding`, a `[batch, length]` mask of ones over the real tokens.
    func callAsFunction(_ features: MLXArray, padding: MLXArray) -> MLXArray {
        let (batch, length, dim) = (features.dim(0), features.dim(1), features.dim(2))
        precondition(length % registers.dim(0) == 0, "length \(length) must divide by the register count")
        var x = Self.frontAligned(features, padding: padding)
        // Registers tiled over the sequence, so position `p` gets register `p mod count`.
        let bank = MLX.tiled(registers, repetitions: [length / registers.dim(0), 1]).asType(x.dtype)
        let validCount = MLX.sum(padding .!= 0, axis: 1)[0..., .newAxis]
        let positions = MLXArray(Array(0..<Int32(length)))[.newAxis, 0...]
        let isToken = (positions .< validCount)[0..., 0..., .newAxis]
        x = MLX.where(isToken, x, MLX.broadcast(bank[.newAxis, 0..., 0...], to: [batch, length, dim]))

        let table = rotary.table(positions: MLXArray(Array(0..<Int32(length)))[.newAxis, 0...])
        for block in blocks {
            x = block(x, rotary: table)
        }
        return LTX2RMSNorm.normalize(x, eps: eps)
    }

    /// The real tokens moved to the front of each row, in their order, with the padding behind
    /// them: a stable sort of the mask, which for a left-padded prompt is a rotation.
    static func frontAligned(_ x: MLXArray, padding: MLXArray) -> MLXArray {
        let length = x.dim(1)
        let positions = MLXArray(Array(0..<Int32(length)))[.newAxis, 0...]
        // Pads sort after tokens, and among themselves by position, which is what makes it stable.
        let keys = MLX.where(padding .!= 0, positions, positions + Int32(length))
        let order = MLX.argSort(keys, axis: 1)
        return MLX.takeAlong(x, order[0..., 0..., .newAxis], axis: 1)
    }
}
