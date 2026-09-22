import Foundation
import MLX

/// A prompt, and any reference pictures with it, turned into the conditioning the transformer
/// reads.
///
/// The whole of `_get_qwen_prompt_embeds` past the tokenizer, in order: grow each
/// `<|image_pad|>` into its picture's run of slots, embed, put the tower's merged output over
/// those rows, run all 36 decoder layers with the three-axis positions and the DeepStack taps,
/// and throw away the first `dropIndex` states, which are the system turn's.
///
/// The tokenizer is a parameter of `encode(_:tokenizer:references:)` rather than a stored
/// property, so the whole of this runs against a doll's-house model with hand-written ids and
/// no 33 GB release anywhere near it.
///
/// A negative prompt goes through the same call. The reference encodes it separately too, and
/// at batch one there is no padding and so no mask, which is why this answers one prompt at a
/// time rather than a batch.
public final class QwenImage21PromptEncoder {
    private let model: Qwen3VLLanguageModel
    private let tower: Qwen3VLVisionTower?
    private let configuration: Qwen3VLTextConfiguration
    private let processor: QwenImage21ProcessorConfiguration

    /// - Parameter tower: Nil for a build that never reads a picture; a prompt with references
    ///   then throws rather than encoding a run of empty slots.
    public init(
        model: Qwen3VLLanguageModel,
        tower: Qwen3VLVisionTower?,
        configuration: Qwen3VLTextConfiguration,
        processor: QwenImage21ProcessorConfiguration
    ) {
        self.model = model
        self.tower = tower
        self.configuration = configuration
        self.processor = processor
    }

    /// The conditioning for token `ids`, which already carry the template and one
    /// `<|image_pad|>` per picture.
    ///
    /// - Parameter references: Each `[height, width, 3]` or `[height, width, 4]` over 0 to 255.
    ///   A fourth channel is flattened over white here, because that is the one copy of a
    ///   reference the tower reads and the autoencoder's keeps all four.
    public func encode(
        ids: [Int], references: [MLXArray] = []
    ) throws -> QwenImage21PromptEncoding {
        let prepared = try references.map {
            try Qwen3VLImagePreprocessing.patches(
                of: Qwen3VLImagePreprocessing.towerInput($0), processor: processor)
        }
        let layout =
            prepared.isEmpty
            ? Qwen3VLTokenLayout(ids: ids)
            : try Qwen3VLTokenLayout(
                expanding: ids, imageTokenID: configuration.imageTokenID,
                grids: prepared.map(\.grid), mergeSize: processor.mergeSize)

        let tokens = MLXArray(layout.ids.map { Int32($0) }).reshaped(1, layout.count)
        var embeddings = model.embedded(tokens)
        var deepStack: Qwen3VLDeepStack?
        if !prepared.isEmpty {
            (embeddings, deepStack) = try read(prepared, into: embeddings, layout: layout)
        }

        let positions =
            prepared.isEmpty
            ? Qwen3VLRotary.textPositions(count: layout.count)
            : Qwen3VLPositionIDs.positions(
                layout: layout, grids: prepared.map(\.grid), mergeSize: processor.mergeSize)

        let hidden = try model.hiddenStates(embeddings, positions: positions, deepStack: deepStack)
        return kept(hidden, layout: layout)
    }

    /// The tower's slots written over the embedding rows, and its taps spread for DeepStack.
    private func read(
        _ prepared: [(patches: MLXArray, grid: Qwen3VLImageGrid)],
        into embeddings: MLXArray,
        layout: Qwen3VLTokenLayout
    ) throws -> (MLXArray, Qwen3VLDeepStack) {
        guard let tower else {
            throw Qwen3VLEncodingError.slotCountDisagrees(slots: 0, expected: layout.slotCount)
        }
        let features = prepared.map { tower($0.patches, grid: $0.grid) }
        let slots = MLX.concatenated(features.map(\.slots), axis: 0)
        guard slots.dim(0) == layout.slotCount else {
            throw Qwen3VLEncodingError.slotCountDisagrees(
                slots: slots.dim(0), expected: layout.slotCount)
        }
        let taps = (0..<features[0].deepStack.count).map { tap in
            MLX.concatenated(features.map { $0.deepStack[tap] }, axis: 0)
        }
        return (
            Qwen3VLSlotWriting.replacing(embeddings, with: slots, runs: layout.imageRuns),
            Qwen3VLDeepStack(taps: taps, runs: layout.imageRuns, tokens: layout.count)
        )
    }

    /// The states and the layout past the system turn: `_drop_idx` applied to both.
    private func kept(
        _ hidden: MLXArray, layout: Qwen3VLTokenLayout
    ) -> QwenImage21PromptEncoding {
        let drop = QwenImage21PromptTemplate.dropIndex
        let dropped = layout.droppingFirst(drop)
        let pad = dropped.ids.map { Int32($0 == configuration.imageTokenID ? 1 : 0) }
        return QwenImage21PromptEncoding(
            embeddings: hidden[0..., drop..., 0...],
            length: dropped.count,
            imagePadMask: MLXArray(pad).reshaped(1, dropped.count),
            imageRuns: dropped.imageRuns)
    }
}
