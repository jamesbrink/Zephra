import Foundation
import MLX
import Testing
import ZephraQuantization
import ZephraTestSupport

@testable import Wan

/// Every tensor the release's autoencoder ships, accounted for before a weight is read.
///
/// The tree is built at the real size -- lazily, MLX allocates nothing until an array is
/// evaluated -- and its parameter paths are compared with the file's header, so a miscounted
/// block, a shortcut this port forgot or a stage built one channel wide shows up as a name or
/// a shape on one side and not the other. Headers only: the 2.8 GB file is checked in a second.
@Suite("the real autoencoder's tensors are exactly the tree's parameters")
struct VAEWeightKeyTests {
    static let file = "vae/diffusion_pytorch_model.safetensors"

    @Test(
        "every tensor in the file is a parameter path of the tree, and every path is in the file",
        .enabled(if: SnapshotUnderTest.wan.hasRelease))
    func namesMatch() throws {
        let release = try #require(SnapshotUnderTest.wan.release)
        let header = try SafeTensorsHeader(contentsOf: release.appending(path: Self.file))
        let published = Set(header.entries.map(\.name))
        let claimed = Set(WanVideoAutoencoder(.wan22).parameters().flattened().map(\.0))
        #expect(published.count == 196)
        let absent = claimed.subtracting(published)
        let unclaimed = published.subtracting(claimed)
        #expect(absent.isEmpty, Comment(rawValue: "expected but absent: \(absent.sorted().prefix(8))"))
        #expect(unclaimed.isEmpty, Comment(rawValue: "present but unclaimed: \(unclaimed.sorted().prefix(8))"))
    }

    @Test(
        "every parameter's shape, put back in the checkpoint's layout, is the file's",
        .enabled(if: SnapshotUnderTest.wan.hasRelease))
    func shapesMatch() throws {
        let release = try #require(SnapshotUnderTest.wan.release)
        let header = try SafeTensorsHeader(contentsOf: release.appending(path: Self.file))
        let published = header.entries.reduce(into: [String: [Int]]()) { $0[$1.name] = $1.shape }
        for (path, parameter) in WanVideoAutoencoder(.wan22).parameters().flattened() {
            #expect(WanVAEWeights.checkpointShape(of: path, parameter.shape) == published[path], "\(path)")
        }
    }

    @Test(
        "the release's config says what wan22 says",
        .enabled(if: SnapshotUnderTest.wan.hasRelease))
    func configurationMatchesTheFile() throws {
        let release = try #require(SnapshotUnderTest.wan.release)
        let read = try WanVAEConfiguration(readingFrom: release.appending(path: "vae/config.json"))
        #expect(read == .wan22)
    }

    @Test("the fixture's tensors go into the tree's layouts and come back to their own shapes")
    func layoutsRoundTrip() throws {
        let fixture = try Fixture.load("vae_decoder")
        let weights = Fixture.weights(fixture, under: "")
        let sanitized = WanVAEWeights.sanitized(weights)
        #expect(sanitized.count == weights.count)
        for (name, tensor) in weights {
            #expect(WanVAEWeights.checkpointShape(of: name, sanitized[name]!.shape) == tensor.shape, "\(name)")
        }
        // A kernel's channels move to the end, a gain flattens, a bias stays.
        #expect(sanitized["decoder.conv_in.weight"]?.shape == [16, 3, 3, 3, 4])
        #expect(sanitized["decoder.up_blocks.0.upsampler.resample.1.weight"]?.shape == [16, 3, 3, 16])
        #expect(sanitized["decoder.mid_block.attentions.0.norm.gamma"]?.shape == [16])
        #expect(sanitized["decoder.norm_out.gamma"]?.shape == [8])
        #expect(sanitized["decoder.conv_out.bias"]?.shape == [12])
    }

    @Test("the doll's house fixtures cover both halves of the tree exactly, nothing more or less")
    func fixturesCoverTheTree() throws {
        let encoder = Set(Fixture.weights(try Fixture.load("vae_encoder"), under: "").keys)
        let decoder = Set(Fixture.weights(try Fixture.load("vae_decoder"), under: "").keys)
        let tree = Set(WanVideoAutoencoder(VAEEncoderParityTests.dollsHouse).parameters().flattened().map(\.0))
        #expect(encoder.intersection(decoder).isEmpty)
        #expect(encoder.union(decoder) == tree)
    }

    @Test("the real layout's arithmetic gives four frames a latent frame and 16 pixels a cell")
    func compression() {
        let configuration = WanVAEConfiguration.wan22
        #expect(configuration.encoderWidths == [160, 160, 320, 640, 640])
        #expect(configuration.decoderWidths == [1024, 1024, 1024, 512, 256])
        #expect(configuration.spatialCompression == 16)
        #expect(configuration.temporalCompression == 4)
        #expect(configuration.latentFrames(forPixelFrames: 1) == 1)
        #expect(configuration.latentFrames(forPixelFrames: 121) == 31)
        #expect(configuration.pixelFrames(forLatentFrames: 31) == 121)
        #expect(WanLatentNormalization.wan22.mean.count == 48)
    }

    @Test("normalising and denormalising are each other's inverse, channel by channel")
    func normalizationRoundTrips() {
        let normalization = WanLatentNormalization(mean: [1, -2, 0.5], std: [2, 0.5, 4])
        let latent = MLXArray((0..<12).map(Float.init), [1, 3, 2, 1, 2])
        let normalized = normalization.normalize(latent)
        // Channel 1 at (0, 0): (4 - -2) / 0.5 = 12.
        #expect(normalized[0, 1, 0, 0, 0].item(Float.self) == 12)
        #expect(Fixture.maxAbsoluteDifference(normalization.denormalize(normalized), latent) < 1e-6)
    }
}
