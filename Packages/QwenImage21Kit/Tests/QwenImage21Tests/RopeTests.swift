import Foundation
import MLX
import Testing
import ZephraMLX

@testable import QwenImage21

@Suite("The rotary table is the reference's, axis by axis")
struct RopeTests {
    @Test("the three layouts' tables match the reference")
    func tables() throws {
        let fixture = try Fixture.load("rope")
        let rope = QwenImage21Rope(axesDim: JointLayoutFixture.axesDim)
        for label in JointLayoutFixture.labels {
            let layout = try JointLayoutFixture.layout(label, in: fixture)
            let table = rope.frequencies(QwenImage21RopePositions(layout))
            let cos = try #require(fixture["\(label).cos"])
            let sin = try #require(fixture["\(label).sin"])
            #expect(table.cos.shape == cos.shape, Comment(rawValue: "\(label)'s shape"))
            #expect(
                Fixture.maxAbsoluteDifference(table.cos, cos) < 1e-5,
                Comment(rawValue: "\(label)'s cosines"))
            #expect(
                Fixture.maxAbsoluteDifference(table.sin, sin) < 1e-5,
                Comment(rawValue: "\(label)'s sines"))
        }
    }

    @Test("text advances one position an axis and a block freezes the frame axis")
    func textAndFramePositions() throws {
        let fixture = try Fixture.load("rope")
        let layout = try JointLayoutFixture.layout("edit", in: fixture)
        let positions = QwenImage21RopePositions(layout)

        // Four text tokens at 0..3, then the 2x4 condition frozen at 4, then three text tokens
        // starting where the counter reached: 4 + max(2, 4) = 8. Then the 3x4 target, frozen
        // at 11.
        #expect(Array(positions.frame.prefix(4)) == [0, 1, 2, 3])
        #expect(Array(positions.frame[4..<12]) == Array(repeating: 4, count: 8))
        #expect(Array(positions.frame[12..<15]) == [8, 9, 10])
        #expect(Array(positions.frame[15...]) == Array(repeating: 11, count: 12))
    }

    @Test("a block's rows and columns are a zero-centred raster grid, negatives and all")
    func centredGrid() throws {
        let fixture = try Fixture.load("rope")
        let layout = try JointLayoutFixture.layout("edit", in: fixture)
        let positions = QwenImage21RopePositions(layout)

        // The 2x4 condition: rows -1, 0 with four columns each, columns -2..1 per row.
        #expect(Array(positions.height[4..<12]) == [-1, -1, -1, -1, 0, 0, 0, 0])
        #expect(Array(positions.width[4..<12]) == [-2, -1, 0, 1, -2, -1, 0, 1])
        // The 3x4 target: an odd height centres as -2, -1, 0.
        #expect(
            Array(positions.height[15...])
                == [-2, -2, -2, -2, -1, -1, -1, -1, 0, 0, 0, 0])
        // Text positions carry the frame counter on all three axes.
        #expect(Array(positions.height.prefix(4)) == [0, 1, 2, 3])
        #expect(Array(positions.width[12..<15]) == [8, 9, 10])
    }

    /// The reference reads a negative position out of the tail of a 9216-row table, where row
    /// `9216 - k` holds `-k`. This port computes the angle from the position, so the check is
    /// that the two agree: the cosine at a negative row is the cosine of a negative angle, not
    /// of a very large positive one.
    @Test("a negative row position is a negative angle, not a wrapped table index")
    func negativePositionsAreNegativeAngles() {
        let rope = QwenImage21Rope(axesDim: [4, 6, 6])
        let table = rope.frequencies(
            QwenImage21RopePositions(frame: [0], height: [-2], width: [0]))
        let opposite = rope.frequencies(
            QwenImage21RopePositions(frame: [0], height: [2], width: [0]))
        // cos(-x) == cos(x) and sin(-x) == -sin(x), which a table index of 9214 would not give.
        #expect(Fixture.maxAbsoluteDifference(table.cos, opposite.cos) < 1e-6)
        #expect(Fixture.maxAbsoluteDifference(table.sin, -opposite.sin) < 1e-6)
    }
}
