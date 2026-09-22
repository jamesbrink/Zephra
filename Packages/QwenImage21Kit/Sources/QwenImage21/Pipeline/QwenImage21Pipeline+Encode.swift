import Foundation
import MLX
import ZephraMLX

/// The prompt, the reference pictures and the layout they imply — everything the loop reads
/// that a step does not change.
extension QwenImage21Pipeline {
    /// Runs the vision-language encoder over the prompt (and over the negative prompt, when
    /// guidance asks for one), encodes every reference through the autoencoder, and lays the
    /// joint sequence out.
    ///
    /// **Two calls, never a padded batch.** The reference encodes the prompt and the negative
    /// prompt separately and its own `encode_prompt` throws the mask away when nothing was
    /// padded (`if prompt_embeds_mask.all(): prompt_embeds_mask = None`), so at batch one there
    /// is no padding, no mask, and nothing for `QwenImage21JointLayout.keyValid` to lift. Two
    /// prompts padded to a common length here would introduce exactly the mask the reference
    /// takes care to avoid, and would change both answers.
    func encode(
        _ request: QwenImage21Request,
        pictures: [MLXArray],
        with model: Loaded,
        onProgress: (QwenImage21GenerationProgress) -> Void
    ) throws -> QwenImage21Conditioning {
        let latentHeight = request.height / model.latentScale
        let latentWidth = request.width / model.latentScale
        let shapes =
            pictures.map {
                QwenImage21ImageShape(
                    height: $0.dim(0) / model.latentScale, width: $0.dim(1) / model.latentScale)
            } + [QwenImage21ImageShape(height: latentHeight, width: latentWidth)]

        onProgress(QwenImage21GenerationProgress(stage: .encodingPrompt))
        let positive = try side(
            request.prompt, pictures: pictures, shapes: shapes, with: model)
        let negative =
            request.usesGuidance
            ? try side(request.negativePrompt, pictures: pictures, shapes: shapes, with: model)
            : nil

        return QwenImage21Conditioning(
            positive: positive, negative: negative,
            conditionTokens: try conditionTokens(pictures, with: model, onProgress: onProgress),
            latentHeight: latentHeight, latentWidth: latentWidth)
    }

    /// One prompt encoded, laid out and given a rotary table.
    private func side(
        _ prompt: String,
        pictures: [MLXArray],
        shapes: [QwenImage21ImageShape],
        with model: Loaded
    ) throws -> QwenImage21Conditioning.Side {
        let encoding = try model.encoder.encode(
            prompt, tokenizer: model.tokenizer, references: pictures)
        MLX.eval(encoding.embeddings)
        let layout = try QwenImage21JointLayout(
            imageSlots: slots(encoding, target: shapes[shapes.count - 1]), shapes: shapes)
        return QwenImage21Conditioning.Side(
            text: encoding.embeddings.asType(model.activation),
            layout: layout,
            frequencies: model.rope.frequencies(QwenImage21RopePositions(layout)))
    }

    /// The transformer's `img_mask`: the encoder's own slots, then one appended slot per four
    /// latents of the picture being made.
    ///
    /// Built from `imageRuns` rather than by reading `imagePadMask` back off the device: the
    /// runs are the same fact in the shape the layout wants, and taking them costs no
    /// evaluation at all.
    private func slots(
        _ encoding: QwenImage21PromptEncoding, target: QwenImage21ImageShape
    ) -> [Bool] {
        var marked = [Bool](repeating: false, count: encoding.length)
        for run in encoding.imageRuns {
            for position in run { marked[position] = true }
        }
        return marked
            + [Bool](
                repeating: true,
                count: target.tokenCount / QwenImage21JointLayout.tokensPerSlot)
    }

    /// Every reference picture's latent, normalised, packed and concatenated in order.
    ///
    /// All four channels reach the autoencoder — the flattening over white is the tower's copy
    /// alone — and the pixels are scaled from 0 to 255 into -1 to 1 here, which is the
    /// reference's `VaeImageProcessor.preprocess`.
    private func conditionTokens(
        _ pictures: [MLXArray],
        with model: Loaded,
        onProgress: (QwenImage21GenerationProgress) -> Void
    ) throws -> MLXArray? {
        guard !pictures.isEmpty else { return nil }
        onProgress(QwenImage21GenerationProgress(stage: .encodingReferences))
        let packed = pictures.map { picture -> MLXArray in
            let pixels = picture.expandedDimensions(axis: 0).asType(.float32) / 127.5 - 1
            let latent = model.normalization.normalize(model.autoencoder.encode(pixels))
            return QwenImage21LatentPacking.tokens(latent.transposed(0, 3, 1, 2))
                .asType(model.activation)
        }
        let tokens = packed.count == 1 ? packed[0] : MLX.concatenated(packed, axis: 1)
        MLX.eval(tokens)
        return tokens
    }
}
