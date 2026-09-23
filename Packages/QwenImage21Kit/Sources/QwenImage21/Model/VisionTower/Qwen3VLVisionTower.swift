import Foundation
import MLX
import MLXNN

/// Qwen3-VL's vision tower: 27 blocks over a reference picture's patches, with three DeepStack
/// taps on the way and a two-by-two merge at the end.
///
/// The module paths are the checkpoint's under `model.visual.`, which `Qwen3VLVisionWeights`
/// strips: `patch_embed.proj`, `pos_embed`, `blocks.N.*`, `merger.*` and
/// `deepstack_merger_list.N.*`.
///
/// The taps are **after** blocks 8, 16 and 24 — `deepstack_visual_indexes`, read from the
/// config rather than written down, since the doll's-house fixture taps other blocks. Each one
/// runs through its own post-shuffle merger and is kept; the running hidden state carries on
/// untouched, so the taps are invisible in the tower's own output and only a fixture catches a
/// port that dropped them.
public final class Qwen3VLVisionTower: Module {
    @ModuleInfo(key: "patch_embed") var patchEmbed: Qwen3VLVisionPatchEmbed
    @ModuleInfo(key: "pos_embed") var positionTable: Embedding
    @ModuleInfo(key: "blocks") var blocks: [Qwen3VLVisionBlock]
    @ModuleInfo(key: "merger") var merger: Qwen3VLVisionMerger
    @ModuleInfo(key: "deepstack_merger_list") var deepStackMergers: [Qwen3VLVisionMerger]

    private let positions: Qwen3VLVisionPositionEmbedding
    private let rotary: Qwen3VLVisionRotary
    private let tapIndexes: [Int]

    public init(_ configuration: Qwen3VLTextConfiguration.Vision) {
        _patchEmbed.wrappedValue = Qwen3VLVisionPatchEmbed(configuration)
        _positionTable.wrappedValue = Embedding(
            embeddingCount: configuration.numPositionEmbeddings,
            dimensions: configuration.hiddenSize)
        _blocks.wrappedValue = (0..<configuration.depth).map { _ in
            Qwen3VLVisionBlock(configuration)
        }
        _merger.wrappedValue = Qwen3VLVisionMerger(configuration, afterShuffle: false)
        _deepStackMergers.wrappedValue = configuration.deepstackVisualIndexes.map { _ in
            Qwen3VLVisionMerger(configuration, afterShuffle: true)
        }
        positions = Qwen3VLVisionPositionEmbedding(configuration)
        rotary = Qwen3VLVisionRotary(configuration)
        tapIndexes = configuration.deepstackVisualIndexes
    }

    /// Reads one picture's patches, `[patches, 1536]`, laid out as the preprocessing lays them.
    public func callAsFunction(
        _ patches: MLXArray, grid: Qwen3VLImageGrid
    ) -> Qwen3VLVisionFeatures {
        var x = patchEmbed(patches)
        x = x + positions(grid, table: positionTable).asType(x.dtype)
        let (cos, sin) = rotary.tables(for: grid, dtype: x.dtype)

        var taps: [MLXArray] = []
        for (index, block) in blocks.enumerated() {
            x = block(x, cos: cos, sin: sin)
            guard let tap = tapIndexes.firstIndex(of: index) else { continue }
            taps.append(deepStackMergers[tap](x))
        }
        return Qwen3VLVisionFeatures(slots: merger(x), deepStack: taps)
    }
}
