import Foundation
import MLX
import Testing

@testable import Wan

@Suite("the rotary embedding reproduces the reference's tables and rotation")
struct RotaryEmbeddingTests {
    /// The doll's house the fixture was dumped at: heads twelve wide, so the split is four
    /// channels each for time, height and width, over a grid of three by two by two tokens.
    static let embedding = WanRotaryEmbedding(headDim: 12, maxSeqLen: 32)

    @Test("the head is split four ways as the reference splits it, time taking the remainder")
    func split() {
        #expect(Self.embedding.ladders.map(\.count) == [2, 2, 2])
        let real = WanRotaryEmbedding(headDim: 128, maxSeqLen: 1024)
        #expect(real.ladders.map(\.count) == [22, 21, 21])
        #expect(real.ladders[0][0] == 1)
        #expect(abs(real.ladders[1][1] - 1 / pow(10000, 2.0 / 42)) < 1e-15)
    }

    @Test("the grid's table matches the reference's, one angle per adjacent pair")
    func table() throws {
        let fixture = try Fixture.load("rope")
        let table = Self.embedding.table(frames: 3, height: 2, width: 2)
        #expect(table.tokens == 12)
        #expect(table.frequencies.cos.shape == [12, 6])
        // The reference repeats each angle over both channels of its pair; the even channels
        // are the per-pair table.
        let cos = try #require(fixture["out.cos"])[0, 0..., 0, .stride(by: 2)]
        let sin = try #require(fixture["out.sin"])[0, 0..., 0, .stride(by: 2)]
        #expect(Fixture.maxAbsoluteDifference(table.frequencies.cos, cos) < 1e-6)
        #expect(Fixture.maxAbsoluteDifference(table.frequencies.sin, sin) < 1e-6)
    }

    @Test("a query rotated by the table is the reference's")
    func rotation() throws {
        let fixture = try Fixture.load("rope")
        let table = Self.embedding.table(frames: 3, height: 2, width: 2)
        let rotated = table.rotate(try #require(fixture["in.query"]))
        let expected = try #require(fixture["out.query"])
        #expect(rotated.shape == expected.shape)
        #expect(Fixture.maxAbsoluteDifference(rotated, expected) < 1e-5)
    }

    @Test("the table is built once per grid and again when the grid changes")
    func caching() {
        let model = WanTransformer(TransformerParityTests.configuration)
        let first = model.rotaryTable(frames: 3, height: 2, width: 2)
        let again = model.rotaryTable(frames: 3, height: 2, width: 2)
        #expect(first.frequencies.cos === again.frequencies.cos)
        let other = model.rotaryTable(frames: 2, height: 2, width: 2)
        #expect(other.tokens == 8)
        #expect(first.frequencies.cos !== other.frequencies.cos)
    }
}
