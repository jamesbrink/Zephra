import Foundation
import MLX
import Testing

@testable import QwenImage21

@Suite("The joint sequence interleaves text and latents the way the reference does")
struct JointLayoutTests {
    @Test("every image slot expands four-fold and every other position stays one")
    func padMask() throws {
        let fixture = try Fixture.load("rope")
        for label in JointLayoutFixture.labels {
            let layout = try JointLayoutFixture.layout(label, in: fixture)
            #expect(
                layout.imagePadMask == (try Fixture.flags(fixture, "\(label).imagePadMask")),
                Comment(rawValue: "\(label)'s pad mask"))
        }
    }

    @Test("blocks are cut by the shapes' token counts, never by runs of latents")
    func blockIDs() throws {
        let fixture = try Fixture.load("rope")
        let layouts = try Fixture.load("joint_layout")
        for label in JointLayoutFixture.labels {
            let layout = try JointLayoutFixture.layout(label, in: fixture)
            #expect(
                layout.imageIDs == (try Fixture.ints(layouts, "\(label).imageIDs")),
                Comment(rawValue: "\(label)'s block ids"))
            #expect(
                layout.targetTokenMask
                    == (try Fixture.flags(layouts, "\(label).targetTokenMask")),
                Comment(rawValue: "\(label)'s target mask"))
            #expect(
                layout.prefixLength == (try Fixture.ints(layouts, "\(label).prefixLength"))[0],
                Comment(rawValue: "\(label)'s prefix length"))
        }
    }

    /// `twoConditions` is the case the rule exists for: its two conditions sit two positions
    /// apart with one text token between them, and a port that cut blocks by runs of `true`
    /// would still get two here. The one that would not is two adjacent conditions, which this
    /// checks on its own.
    @Test("two condition images side by side stay two blocks")
    func adjacentConditionsAreNotOneBlock() throws {
        let layout = try QwenImage21JointLayout(
            imageSlots: [false, true, true, true],
            shapes: [
                QwenImage21ImageShape(height: 2, width: 2),
                QwenImage21ImageShape(height: 2, width: 2),
                QwenImage21ImageShape(height: 2, width: 2),
            ])
        #expect(layout.imageIDs == [-1] + Array(repeating: 0, count: 4)
            + Array(repeating: 1, count: 4) + Array(repeating: 2, count: 4))
        #expect(layout.prefixLength == 9)
    }

    @Test("the gather reads text from the encoder and every latent from the latents")
    func sourceIndices() throws {
        let fixture = try Fixture.load("rope")
        let layout = try JointLayoutFixture.layout("edit", in: fixture)
        // Four text tokens, then the 2x4 condition's eight latents, three more text tokens,
        // then the target's twelve. The encoder handed over nine tokens, so the latents start
        // at nine.
        #expect(layout.encoderTokenCount == 9)
        #expect(
            layout.sourceIndices
                == [0, 1, 2, 3] + (9..<17).map { $0 } + [6, 7, 8] + (17..<29).map { $0 })
    }

    @Test("a prompt's padding is lifted onto the text positions in order")
    func keyValid() throws {
        let fixture = try Fixture.load("rope")
        let layout = try JointLayoutFixture.layout("edit", in: fixture)
        // The encoder's nine tokens are four text, two image slots, three text. Dropping the
        // last two text tokens has to land on the last two text positions of the joint
        // sequence, which are positions 13 and 14, not on positions 7 and 8.
        var promptMask = [Bool](repeating: true, count: 9)
        promptMask[7] = false
        promptMask[8] = false
        let valid = try layout.keyValid(promptMask: promptMask)
        #expect(valid.count == layout.sequenceLength)
        #expect(valid.enumerated().filter { !$0.element }.map(\.offset) == [13, 14])
    }

    @Test("a shape set that does not account for the slots is refused")
    func mismatchedShapes() {
        #expect(throws: QwenImage21TransformerError.self) {
            _ = try QwenImage21JointLayout(
                imageSlots: [false, true, true],
                shapes: [QwenImage21ImageShape(height: 2, width: 2)])
        }
        #expect(throws: QwenImage21TransformerError.self) {
            _ = try QwenImage21JointLayout(
                imageSlots: [true], shapes: [QwenImage21ImageShape(height: 1, width: 3)])
        }
    }
}
