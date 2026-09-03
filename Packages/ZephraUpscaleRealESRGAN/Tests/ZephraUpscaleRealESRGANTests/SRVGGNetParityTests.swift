import Foundation
import MLX
import Testing

@testable import ZephraUpscaleRealESRGAN

/// The port against torch's `SRVGGNetCompact`, at the doll's-house size `Tools/dump_reference.py`
/// dumps.
///
/// Tolerances are against the fixture's float32 tensors. The bundled checkpoint is float16 and
/// is never compared by value here -- `BundledWeightsTests` checks it by name and shape only.
@Suite("The network reproduces torch's SRVGGNetCompact")
struct SRVGGNetParityTests {
    @Test("the network reproduces the reference at scale 4")
    func matchesAtScaleFour() throws {
        let fixture = try Fixture.load("srvgg_x4")
        let model = try Fixture.network(fixture, scale: 4)

        let result = model(Fixture.channelsLast(try #require(fixture["net.in.image"])))
        let expected = Fixture.channelsLast(try #require(fixture["net.out.image"]))

        #expect(result.shape == expected.shape)
        let difference = Fixture.maxAbsoluteDifference(result, expected)
        #expect(difference < 1e-4, Comment(rawValue: "the network differs by \(difference)"))
    }

    @Test("the network reproduces the reference at scale 2")
    func matchesAtScaleTwo() throws {
        let fixture = try Fixture.load("srvgg_x2")
        let model = try Fixture.network(fixture, scale: 2)

        let result = model(Fixture.channelsLast(try #require(fixture["net.in.image"])))
        let expected = Fixture.channelsLast(try #require(fixture["net.out.image"]))

        #expect(result.shape == expected.shape)
        let difference = Fixture.maxAbsoluteDifference(result, expected)
        #expect(difference < 1e-4, Comment(rawValue: "the network differs by \(difference)"))
    }

    @Test("the residual branch is a nearest upsample, not a bilinear one")
    func residualIsReplication() throws {
        let fixture = try Fixture.load("srvgg_x4")
        let model = try Fixture.network(fixture, scale: 4)
        let image = Fixture.channelsLast(try #require(fixture["net.in.image"]))

        // What the whole network produced, less what the body and the shuffle produced, is by
        // construction whatever was added -- and it has to be replication, because the network
        // learned to predict the difference from that particular base.
        let residual = model(image) - model.predicted(image)

        // Recovering an addend by subtraction costs one float32 rounding, so the claim is a
        // handful of ulps rather than zero. A bilinear or bicubic base would miss by three
        // orders of magnitude more: it interpolates between neighbours where this repeats them.
        let difference = Fixture.maxAbsoluteDifference(
            residual, NearestUpsample.apply(image, factor: 4))
        #expect(difference < 1e-6, Comment(rawValue: "the residual is not a replication: \(difference)"))

        // And it really is a block rather than a ramp: one input pixel, one channel, covers a
        // 4 by 4 square of one value. An interpolating base would vary across it.
        let block = residual[0..., 0..<4, 0..<4, 0..<1]
        #expect(Fixture.maxAbsoluteDifference(block, MLX.min(block)) < 1e-6)
    }

    @Test("an odd, non-square input comes back at exactly the factor on each edge")
    func shapesFollowTheFactor() throws {
        let four = try Fixture.load("srvgg_x4")
        let two = try Fixture.load("srvgg_x2")
        let image = Fixture.channelsLast(try #require(four["net.in.image"]))

        #expect(image.shape == [1, 6, 5, 3])
        #expect(try Fixture.network(four, scale: 4)(image).shape == [1, 24, 20, 3])
        #expect(try Fixture.network(two, scale: 2)(image).shape == [1, 12, 10, 3])
    }

    @Test("every fixture tensor lands, and every parameter is filled")
    func weightNamesLineUp() throws {
        let fixture = try Fixture.load("srvgg_x4")
        let published = SRVGGNetWeights.sanitized(Fixture.weights(fixture, under: "net."))
        let model = SRVGGNet(Fixture.configuration(scale: 4))
        let wanted = Set(model.parameters().flattened().map(\.0))

        #expect(model.body.count == model.configuration.bodyCount)
        let unplaced = Set(published.keys).subtracting(wanted).sorted()
        #expect(
            unplaced.isEmpty,
            Comment(rawValue: "the tree has no place for \(unplaced.joined(separator: ", "))"))
        let unfilled = wanted.subtracting(published.keys).sorted()
        #expect(
            unfilled.isEmpty,
            Comment(rawValue: "nothing fills \(unfilled.joined(separator: ", "))"))
    }
}
