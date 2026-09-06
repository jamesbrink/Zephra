import Foundation
import MLX
import Testing

@testable import LTX2

@Suite("the rotary embedding reproduces the reference's tables")
struct RotaryEmbeddingTests {
    /// The doll's house the fixture was dumped at: two heads of sixteen over three axes, so the
    /// ladder is five per axis and each token's sixteen angles are padded by one.
    static let video = LTX2RotaryEmbedding(
        heads: 2, headDim: 16, maxPositions: [20, 2048, 2048], theta: 10000)

    @Test("token positions are the midpoints of the pixel-space cells, with the causal first frame")
    func positions() throws {
        let fixture = try Fixture.load("rope")
        let layout = LTX2LatentLayout(frames: 3, height: 2, width: 4)
        let positions = layout.positions(frameRate: 24)
        #expect(positions.shape == [3, 24])
        #expect(Fixture.maxAbsoluteDifference(positions, try #require(fixture["video.midpoints"])) < 1e-6)
        // The first frame is one pixel frame wide, later ones eight; a row's centre is 16 pixels in.
        let times = positions[0].asArray(Float.self)
        #expect(abs(times[0] - 0.5 / 24) < 1e-6)
        #expect(abs(times[8] - 5.0 / 24) < 1e-6)
        #expect(positions[1].asArray(Float.self)[0] == 16)
    }

    @Test("the three-axis video table matches, padding included")
    func videoTable() throws {
        let fixture = try Fixture.load("rope")
        #expect(Self.video.ladder.count == 5)
        #expect(Self.video.padding == 1)
        let table = Self.video.table(positions: try #require(fixture["video.midpoints"]))
        #expect(table.cos.shape == [1, 2, 24, 8])
        #expect(Fixture.maxAbsoluteDifference(table.cos, try #require(fixture["video.cos"])) < 1e-5)
        #expect(Fixture.maxAbsoluteDifference(table.sin, try #require(fixture["video.sin"])) < 1e-5)
    }

    @Test("a one-axis table over 4096 positions matches, which is what the text connector uses")
    func lineTable() throws {
        let fixture = try Fixture.load("rope")
        let line = LTX2RotaryEmbedding(heads: 2, headDim: 16, maxPositions: [4096], theta: 10000)
        #expect(line.ladder.count == 16)
        #expect(line.padding == 0)
        let table = line.table(positions: try #require(fixture["line.positions"]))
        #expect(Fixture.maxAbsoluteDifference(table.cos, try #require(fixture["line.cos"])) < 1e-5)
        #expect(Fixture.maxAbsoluteDifference(table.sin, try #require(fixture["line.sin"])) < 1e-5)
    }

    @Test("rotation is the split form: the two halves of a head's width are the pair")
    func rotation() {
        // A quarter turn on every angle sends [a, b] to [-b, a].
        let quarter = LTX2RotaryTable(
            cos: MLXArray.zeros([1, 1, 1, 2]), sin: MLXArray.ones([1, 1, 1, 2]))
        let x = MLXArray([1, 2, 3, 4] as [Float]).reshaped([1, 1, 4])
        let rotated = quarter.rotate(x)
        #expect(rotated.shape == [1, 1, 1, 4])
        #expect(rotated.asArray(Float.self) == [-3, -4, 1, 2])
    }

    @Test("the ladder is built in double precision")
    func ladderPrecision() {
        // theta^(1/4) * pi / 2 for the second rung of a five-rung ladder, rounded once.
        let expected = Float(Foundation.pow(10000.0, 0.25) * Double.pi / 2)
        #expect(Self.video.ladder[1] == expected)
        #expect(Self.video.ladder[0] == Float(Double.pi / 2))
    }
}
