import Foundation
import MLX
import Testing

@testable import QwenImage21

/// The tower and the decoder read together, which is the only way to check DeepStack.
///
/// The fixture is a whole doll's-house `Qwen3VLModel` over one picture, hooked the way the
/// pipeline hooks the real one, so the hidden state it carries has every part of the image path
/// in it: the merged slots written over the `<|image_pad|>` rows before layer 0, the three-axis
/// positions, and the three taps added after layers 0, 1 and 2.
///
/// Which layers those are is the claim worth stating twice. The reference's condition is
/// `layer_idx in range(len(deepstack_visual_embeds))` — a **list index**, not a configured
/// depth — so with three taps it is layers 0, 1 and 2 whatever `deepstack_visual_indexes` says
/// the tower took them from. The doll's house taps blocks 1, 2 and 3 of the tower and injects
/// at decoder layers 0, 1 and 2, which is what separates the two numbers here.
@Suite("DeepStack lands at decoder layers 0, 1 and 2, at the picture's slots")
struct DeepStackTests {
    private static let grid = Qwen3VLImageGrid(rows: 4, columns: 4)

    @Test("a prompt with a picture matches the reference's whole hidden state")
    func theJointForwardMatches() throws {
        let fixture = try Fixture.load("vision")
        let encoding = try encoded(fixture)
        let reference = try #require(fixture["joint.out.hidden"])

        // The encoder drops the system turn, which the doll's-house ids do not have, so the
        // comparison is against the states the reference kept from the same offset.
        let drop = QwenImage21PromptTemplate.dropIndex
        _ = drop
        let difference = Fixture.maxAbsoluteDifference(encoding.hidden, reference)
        #expect(difference < 1e-4, Comment(rawValue: "the joint state differs by \(difference)"))
    }

    @Test("the injection is at the picture's slots and nowhere else")
    func theInjectionIsAtTheSlots() throws {
        let fixture = try Fixture.load("vision")
        let tower = try Qwen3VLDollHouse.visionTower(fixture, prefix: "joint.visual.")
        let features = tower(try #require(fixture["joint.in.pixels"]), grid: Self.grid)
        let deepStack = Qwen3VLDeepStack(
            taps: features.deepStack, runs: [2..<6], tokens: 8)

        #expect(deepStack.layerCount == 3)
        for addition in deepStack.additions {
            #expect(addition.shape == [1, 8, 32])
            // Zero outside the run, the tap inside it.
            #expect(MLX.max(MLX.abs(addition[0..., 0..<2, 0...])).item(Float.self) == 0)
            #expect(MLX.max(MLX.abs(addition[0..., 6..<8, 0...])).item(Float.self) == 0)
            #expect(MLX.max(MLX.abs(addition[0..., 2..<6, 0...])).item(Float.self) > 0)
        }
    }

    @Test("dropping the taps changes the answer, so they are not decoration")
    func theTapsAreLoadBearing() throws {
        let fixture = try Fixture.load("vision")
        let withTaps = try encoded(fixture)
        let withoutTaps = try encoded(fixture, injecting: false)

        let difference = Fixture.maxAbsoluteDifference(withTaps.hidden, withoutTaps.hidden)
        #expect(difference > 1e-3, Comment(rawValue: "DeepStack moved the state by only \(difference)"))
    }

    @Test("a tap added after the wrong layer is a different answer")
    func theLayerOrderMatters() throws {
        let fixture = try Fixture.load("vision")
        let straight = try encoded(fixture)
        let reversed = try encoded(fixture, reversingTaps: true)

        // Three taps in the wrong order still add the same three tensors at the same rows, so
        // nothing about the shapes or the slots catches this; only the arithmetic does.
        let difference = Fixture.maxAbsoluteDifference(straight.hidden, reversed.hidden)
        #expect(difference > 1e-4, Comment(rawValue: "tap order changed the state by only \(difference)"))
    }

    /// The doll's-house joint forward: tower, slots, positions, DeepStack, decoder.
    private func encoded(
        _ fixture: [String: MLXArray], injecting: Bool = true, reversingTaps: Bool = false
    ) throws -> (hidden: MLXArray, layout: Qwen3VLTokenLayout) {
        let configuration = try Qwen3VLDollHouse.configuration()
        let model = try Qwen3VLDollHouse.languageModel(fixture, prefix: "joint.language_model.")
        let tower = try Qwen3VLDollHouse.visionTower(fixture, prefix: "joint.visual.")

        let layout = try Qwen3VLTokenLayout(
            expanding: [1, 2, configuration.imageTokenID, 3, 4],
            imageTokenID: configuration.imageTokenID, grids: [Self.grid], mergeSize: 2)
        let features = tower(try #require(fixture["joint.in.pixels"]), grid: Self.grid)
        let tokens = MLXArray(layout.ids.map { Int32($0) }).reshaped(1, layout.count)
        let embeddings = Qwen3VLSlotWriting.replacing(
            model.embedded(tokens), with: features.slots, runs: layout.imageRuns)
        let taps = reversingTaps ? features.deepStack.reversed() : features.deepStack
        let deepStack =
            injecting
            ? Qwen3VLDeepStack(
                taps: Array(taps), runs: layout.imageRuns, tokens: layout.count) : nil

        let positions = Qwen3VLPositionIDs.positions(
            layout: layout, grids: [Self.grid], mergeSize: 2)
        return (
            try model.hiddenStates(embeddings, positions: positions, deepStack: deepStack), layout
        )
    }
}
