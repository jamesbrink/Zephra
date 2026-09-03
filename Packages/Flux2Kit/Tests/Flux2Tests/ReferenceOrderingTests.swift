import Foundation
import MLX
import Testing

@testable import Flux2

@Suite("A reference picture sits after the image being made, on its own image index")
struct ReferenceOrderingTests {
    /// The fixture's packed tensors flattened the way the pipeline flattens them.
    private static func references(_ fixture: [String: MLXArray]) throws
        -> [Flux2ReferenceConditioning.Reference]
    {
        try (0..<2).map { index in
            let packed = try #require(fixture["reference\(index).packed"])
            return Flux2ReferenceConditioning.Reference(
                tokens: Flux2LatentPacking.tokens(packed),
                ids: Flux2PositionIDs.image(
                    height: packed.dim(2), width: packed.dim(3),
                    imageIndex: Flux2PositionIDs.referenceImageIndex(index)))
        }
    }

    @Test("tokens and ids concatenate in the reference's order, target first")
    func orderMatchesReference() throws {
        let fixture = try Fixture.load("reference_conditioning")
        let target = try #require(fixture["target.packed"])
        let (tokens, ids) = Flux2ReferenceConditioning.concatenated(
            target: Flux2LatentPacking.tokens(target),
            targetIDs: Flux2PositionIDs.image(height: target.dim(2), width: target.dim(3)),
            references: try Self.references(fixture))
        let expectedTokens = try #require(fixture["combined.tokens"])
        #expect(tokens.shape == expectedTokens.shape)
        #expect(Fixture.maxAbsoluteDifference(tokens, expectedTokens) == 0)
        let expectedIDs = try #require(fixture["combined.ids"]).asArray(Int32.self)
        #expect(ids.flatMap { $0 }.map(Int32.init) == expectedIDs)
    }

    @Test("the image index column reads 0 for the target, then 10 and 20 for the references")
    func imageIndexColumn() throws {
        let fixture = try Fixture.load("reference_conditioning")
        let target = try #require(fixture["target.packed"])
        let (_, ids) = Flux2ReferenceConditioning.concatenated(
            target: Flux2LatentPacking.tokens(target),
            targetIDs: Flux2PositionIDs.image(height: target.dim(2), width: target.dim(3)),
            references: try Self.references(fixture))
        let column = ids.map { $0[0] }
        #expect(column == Array(repeating: 0, count: 12) + Array(repeating: 10, count: 6)
            + Array(repeating: 20, count: 8))
    }

    @Test("swapping two references changes the ids, so the index is per position and not per call")
    func swappingChangesIDs() throws {
        let fixture = try Fixture.load("reference_conditioning")
        let target = try #require(fixture["target.packed"])
        let targetIDs = Flux2PositionIDs.image(height: target.dim(2), width: target.dim(3))
        let ordered = try Self.references(fixture)
        let swapped = [ordered[1], ordered[0]].enumerated().map { index, reference in
            Flux2ReferenceConditioning.Reference(
                tokens: reference.tokens,
                ids: reference.ids.map { [Flux2PositionIDs.referenceImageIndex(index)] + $0.dropFirst() })
        }
        let a = Flux2ReferenceConditioning.concatenated(
            target: Flux2LatentPacking.tokens(target), targetIDs: targetIDs, references: ordered).ids
        let b = Flux2ReferenceConditioning.concatenated(
            target: Flux2LatentPacking.tokens(target), targetIDs: targetIDs, references: swapped).ids
        #expect(a != b)
    }

    @Test("the shift counts the target's tokens alone, references or not")
    func shiftIgnoresReferences() throws {
        let fixture = try Fixture.load("reference_conditioning")
        let mu = try #require(fixture["mu"]).item(Float.self)
        #expect(abs(Float(EmpiricalShift.mu(imageSequenceLength: 12, steps: 4)) - mu) < 1e-6)
    }

    @Test("no references means the target passes through untouched")
    func noReferences() {
        let target = MLXArray(0..<24).asType(.float32).reshaped([1, 12, 2])
        let ids = Flux2PositionIDs.image(height: 3, width: 4)
        let (tokens, outIDs) = Flux2ReferenceConditioning.concatenated(
            target: target, targetIDs: ids, references: [])
        #expect(Fixture.maxAbsoluteDifference(tokens, target) == 0)
        #expect(outIDs == ids)
    }
}
