import Foundation
import MLX
import Testing

@testable import QwenImage21

/// The encoder end to end at doll's-house size: ids in, the conditioning the transformer reads
/// out, with the system turn thrown away.
///
/// `dropIndex` is the point of most of this. The reference derives it from the chat template
/// and then slices every sample's hidden states by it; a count one out shifts every
/// conditioning vector by a token, and the image-pad mask has to move by exactly the same
/// amount or a reference's slots sit beside the wrong latents.
@Suite("The prompt encoder drops the system turn and keeps the rest lined up")
struct PromptEncoderTests {
    private static let grid = Qwen3VLImageGrid(rows: 4, columns: 4)

    @Test("the states begin at the user turn: length is the ids less the drop")
    func theSystemTurnIsDropped() throws {
        let fixture = try Fixture.load("vision")
        let encoder = try Self.encoder(fixture)
        let ids = Array(repeating: 7, count: QwenImage21PromptTemplate.dropIndex + 5)

        let encoding = try encoder.encode(ids: ids)

        #expect(encoding.length == 5)
        #expect(encoding.embeddings.shape == [1, 5, 32])
        #expect(encoding.imagePadMask.shape == [1, 5])
    }

    @Test("the kept states are the tail of the whole run, not a second forward pass")
    func theKeptStatesAreTheTail() throws {
        let fixture = try Fixture.load("vision")
        let encoder = try Self.encoder(fixture)
        let model = try Qwen3VLDollHouse.languageModel(fixture, prefix: "joint.language_model.")
        let ids = (0..<(QwenImage21PromptTemplate.dropIndex + 4)).map { $0 % 50 }

        let encoding = try encoder.encode(ids: ids)
        let whole = try model.hiddenStates(
            model.embedded(MLXArray(ids.map { Int32($0) }).reshaped(1, ids.count)),
            positions: Qwen3VLRotary.textPositions(count: ids.count))

        // The prompt is encoded once and sliced. Encoding the kept tokens on their own would
        // give different states, since the dropped ones are in every later token's attention.
        let difference = Fixture.maxAbsoluteDifference(
            encoding.embeddings, whole[0..., QwenImage21PromptTemplate.dropIndex..., 0...])
        #expect(difference == 0, Comment(rawValue: "the tail moved by \(difference)"))
    }

    @Test("the image-pad mask and the runs move with the drop")
    func theImagePadMaskMovesWithTheDrop() throws {
        let fixture = try Fixture.load("vision")
        let encoder = try Self.encoder(fixture)
        let configuration = try Qwen3VLDollHouse.configuration()
        let drop = QwenImage21PromptTemplate.dropIndex
        let ids =
            Array(repeating: 7, count: drop) + [1, configuration.imageTokenID, 2]

        let encoding = try encoder.encode(ids: ids, references: [Self.picture()])

        // Four slots for a four-by-four grid merged two-by-two, at positions 1 through 4 of
        // what is kept, which is 1 through 4 of the ids past the drop.
        #expect(encoding.length == 3 + 3)
        #expect(encoding.imageRuns == [1..<5])
        #expect(
            encoding.imagePadMask.reshaped(-1).asArray(Int32.self) == [0, 1, 1, 1, 1, 0])
    }

    @Test("a template whose pad count is not the picture count is refused")
    func aMismatchedPadCountIsRefused() throws {
        let fixture = try Fixture.load("vision")
        let encoder = try Self.encoder(fixture)
        let configuration = try Qwen3VLDollHouse.configuration()

        #expect(throws: Qwen3VLEncodingError.imagePadCountDisagrees(pads: 2, pictures: 1)) {
            _ = try encoder.encode(
                ids: Array(repeating: 7, count: QwenImage21PromptTemplate.dropIndex)
                    + [configuration.imageTokenID, configuration.imageTokenID],
                references: [Self.picture()])
        }
    }

    @Test("a picture handed to an encoder with no tower is refused rather than left empty")
    func aPictureWithNoTowerIsRefused() throws {
        let fixture = try Fixture.load("vision")
        let configuration = try Qwen3VLDollHouse.configuration()
        let encoder = QwenImage21PromptEncoder(
            model: try Qwen3VLDollHouse.languageModel(fixture, prefix: "joint.language_model."),
            tower: nil, configuration: configuration,
            processor: try Qwen3VLDollHouse.processor())

        #expect(throws: Qwen3VLEncodingError.slotCountDisagrees(slots: 0, expected: 4)) {
            _ = try encoder.encode(
                ids: Array(repeating: 7, count: QwenImage21PromptTemplate.dropIndex)
                    + [configuration.imageTokenID],
                references: [Self.picture()])
        }
    }

    private static func encoder(_ fixture: [String: MLXArray]) throws -> QwenImage21PromptEncoder {
        QwenImage21PromptEncoder(
            model: try Qwen3VLDollHouse.languageModel(fixture, prefix: "joint.language_model."),
            tower: try Qwen3VLDollHouse.visionTower(fixture, prefix: "joint.visual."),
            configuration: try Qwen3VLDollHouse.configuration(),
            processor: try Qwen3VLDollHouse.processor())
    }

    /// A 16 by 16 picture, which at the doll's patch size of four is a four-by-four grid and so
    /// four slots.
    private static func picture() -> MLXArray {
        MLXArray((0..<(16 * 16 * 3)).map { Float($0 % 256) }).reshaped(16, 16, 3)
    }
}
