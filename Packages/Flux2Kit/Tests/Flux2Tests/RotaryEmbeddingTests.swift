import Foundation
import MLX
import Testing

@testable import Flux2

@Suite("The rotary tables match the reference's four-axis embedding")
struct RotaryEmbeddingTests {
    private static let embedding = Flux2RotaryEmbedding(theta: 2000, axesDim: [4, 4, 4, 4])

    @Test("every dumped id set produces the reference's cosines and sines")
    func tablesMatchReference() throws {
        let fixture = try Fixture.load("rope")
        for label in ["text", "image", "edit"] {
            let ids = try #require(fixture["\(label).ids"]).asArray(Int32.self)
            let rows = ids.count / 4
            let idList = (0..<rows).map { row in (0..<4).map { Int(ids[row * 4 + $0]) } }
            let table = Self.embedding.frequencies(ids: idList)
            let cos = try #require(fixture["\(label).cos"])
            let sin = try #require(fixture["\(label).sin"])
            #expect(table.cos.shape == cos.shape, Comment(rawValue: label))
            #expect(Fixture.maxAbsoluteDifference(table.cos, cos) < 1e-5, Comment(rawValue: label))
            #expect(Fixture.maxAbsoluteDifference(table.sin, sin) < 1e-5, Comment(rawValue: label))
        }
    }

    @Test("the ids the pipeline builds are the reference's")
    func positionIDs() throws {
        let fixture = try Fixture.load("rope")
        let text = Flux2PositionIDs.text(count: 5).flatMap { $0 }.map(Int32.init)
        #expect(text == (try #require(fixture["text.ids"])).asArray(Int32.self))
        let image = Flux2PositionIDs.image(height: 3, width: 4).flatMap { $0 }.map(Int32.init)
        #expect(image == (try #require(fixture["image.ids"])).asArray(Int32.self))
        let edit =
            (Flux2PositionIDs.image(height: 2, width: 3)
                + Flux2PositionIDs.image(height: 3, width: 2,
                                         imageIndex: Flux2PositionIDs.referenceImageIndex(0)))
            .flatMap { $0 }.map(Int32.init)
        #expect(edit == (try #require(fixture["edit.ids"])).asArray(Int32.self))
    }

    @Test("rotation keeps every pair's magnitude")
    func rotationPreservesMagnitude() {
        let table = Self.embedding.frequencies(ids: Flux2PositionIDs.image(height: 2, width: 3))
        let x = MLXRandom.normal([1, 6, 2, 16], key: MLXRandom.key(3))
        let rotated = table.rotate(x, computeDType: .float32)
        let before = MLX.sum(x.reshaped([1, 6, 2, 8, 2]).square(), axis: -1)
        let after = MLX.sum(rotated.reshaped([1, 6, 2, 8, 2]).square(), axis: -1)
        #expect(Fixture.maxAbsoluteDifference(before, after) < 1e-5)
    }

    @Test("position zero on every axis is the identity")
    func originIsIdentity() {
        let table = Self.embedding.frequencies(ids: [[0, 0, 0, 0]])
        let x = MLXRandom.normal([1, 1, 2, 16], key: MLXRandom.key(4))
        #expect(Fixture.maxAbsoluteDifference(table.rotate(x, computeDType: .float32), x) < 1e-6)
    }
}
