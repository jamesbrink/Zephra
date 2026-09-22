import Foundation

/// How text and latents interleave in the one sequence the transformer attends over.
///
/// This is the part of 2.1 a port gets wrong first. The vision-language encoder produced a
/// sequence with a slot at every `<|image_pad|>`, and the pipeline appended one more slot per
/// four latents of the image being made. **Each slot stands for four latent tokens**, so every
/// slot expands four-fold and every other position stays one, and the image blocks end up
/// exactly where the prompt put them rather than concatenated at the front. At each image
/// position the encoder's own hidden state is then thrown away and replaced by the projected
/// latent: what carries a reference picture into the transformer is the *text* the encoder
/// wrote having looked at it, never the encoder's image embeddings.
///
/// Blocks are cut by the shapes' token counts and **never by runs of `true`**: two condition
/// images side by side with no text between them are one run and two blocks, and merging them
/// would let them attend to each other bidirectionally.
public struct QwenImage21JointLayout: Sendable {
    /// One vision-language image slot stands for a two-by-two group of latent tokens.
    public static let tokensPerSlot = 4

    /// The grids, condition images first and the target last.
    public let shapes: [QwenImage21ImageShape]
    /// `true` at every joint position that holds a latent.
    public let imagePadMask: [Bool]
    /// `-1` at a text position, otherwise the index of the block the position belongs to.
    public let imageIDs: [Int]
    /// `true` at the target image's positions, which are the sequence's trailing run.
    public let targetTokenMask: [Bool]
    /// Where each joint position reads from in `[encoder tokens ++ latent tokens]`, which is
    /// the one gather the forward pass builds the joint sequence with.
    public let sourceIndices: [Int]
    /// How many tokens the encoder handed over: the vision-language sequence before the target
    /// slots were appended.
    public let encoderTokenCount: Int
    /// Everything before the target image: the text and every condition image. Its keys and
    /// values do not change from step to step, which is what the prefix cache is.
    public let prefixLength: Int

    /// Vision-language positions that are text, which the prompt's padding mask is read at.
    private let promptTextSlots: [Int]

    /// The whole sequence.
    public var sequenceLength: Int { imagePadMask.count }
    /// Latent tokens the image being made occupies.
    public var targetTokenCount: Int { shapes.last?.tokenCount ?? 0 }

    /// Lays out `shapes` against the encoder's slot mask.
    ///
    /// - Parameters:
    ///   - imageSlots: `true` at every vision-language image slot, the target's appended slots
    ///     included. This is the transformer's `img_mask`, row zero, since samples share a
    ///     layout.
    ///   - shapes: One grid per block, condition images first and the target last.
    public init(imageSlots: [Bool], shapes: [QwenImage21ImageShape]) throws {
        guard let target = shapes.last else { throw QwenImage21TransformerError.noImageBlocks }
        for shape in shapes where !shape.tokenCount.isMultiple(of: Self.tokensPerSlot) {
            throw QwenImage21TransformerError.blockIsNotWholeSlots(tokens: shape.tokenCount)
        }
        let slotted = imageSlots.filter { $0 }.count * Self.tokensPerSlot
        let accounted = shapes.reduce(0) { $0 + $1.tokenCount }
        guard slotted == accounted, accounted > 0 else {
            throw QwenImage21TransformerError.imageShapesDoNotMatchSlots(
                shapeTokens: accounted, maskTokens: slotted)
        }

        self.shapes = shapes
        let encoderTokens = imageSlots.count - target.tokenCount / Self.tokensPerSlot
        encoderTokenCount = encoderTokens
        promptTextSlots = (0..<encoderTokens).filter { !imageSlots[$0] }

        var pad: [Bool] = []
        var sources: [Int] = []
        var latent = 0
        for (slot, isImage) in imageSlots.enumerated() {
            for _ in 0..<(isImage ? Self.tokensPerSlot : 1) {
                pad.append(isImage)
                sources.append(isImage ? encoderTokens + latent : slot)
                if isImage { latent += 1 }
            }
        }
        imagePadMask = pad
        sourceIndices = sources

        var ids = [Int](repeating: -1, count: pad.count)
        let blocks = shapes.enumerated().flatMap { index, shape in
            [Int](repeating: index, count: shape.tokenCount)
        }
        var consumed = 0
        for position in pad.indices where pad[position] {
            ids[position] = blocks[consumed]
            consumed += 1
        }
        imageIDs = ids
        let lastBlock = shapes.count - 1
        let isTarget = ids.map { $0 == lastBlock }
        targetTokenMask = isTarget
        // Counted rather than subtracted, which is the reference's own arithmetic, and then
        // checked to be the trailing run: every step past the first slices the sequence there
        // and would otherwise recompute the wrong tokens.
        prefixLength = isTarget.filter { !$0 }.count
        guard isTarget[prefixLength...].allSatisfy({ $0 }) else {
            throw QwenImage21TransformerError.imageShapesDoNotMatchSlots(
                shapeTokens: accounted, maskTokens: slotted)
        }
    }

    /// The prompt's padding mask lifted onto the joint sequence.
    ///
    /// Right-padded prompt positions must never be attended to as *keys*. The text positions of
    /// the joint sequence line up, in order, with the non-image positions of the vision-language
    /// sequence — the two are interleaved, so the mask cannot be sliced off as a prefix. Every
    /// latent position is valid.
    public func keyValid(promptMask: [Bool]) throws -> [Bool] {
        guard promptMask.count == encoderTokenCount else {
            throw QwenImage21TransformerError.promptMaskIsTheWrongLength(
                mask: promptMask.count, textPositions: promptTextSlots.count)
        }
        var valid = [Bool](repeating: true, count: sequenceLength)
        var slot = 0
        for position in imagePadMask.indices where !imagePadMask[position] {
            valid[position] = promptMask[promptTextSlots[slot]]
            slot += 1
        }
        return valid
    }
}
