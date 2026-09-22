import Foundation
import MLX
import Testing
import ZephraQuantization
import ZephraTestSupport

@testable import QwenImage21

/// Every tensor the release's autoencoder ships, accounted for before a weight is read.
///
/// The tree is built at the real size -- lazily, MLX allocates nothing until an array is
/// evaluated -- and its parameter paths are compared with the file's header, so a miscounted
/// block, a shortcut this port forgot or a stage built one channel wide shows up as a name or a
/// shape on one side and not the other. Headers only: 1.35 GB is checked in a second.
///
/// **The twelve unreachable keys are claimed here rather than left unlisted.** Six `time_conv`
/// modules exist in the checkpoint and cannot run for a still image, so the tree does not build
/// them; naming them is what keeps "every published key is accounted for" a true statement
/// rather than a count with a hole in it.
///
/// (Named for the file it will merge into when the pipeline's own `WeightKeyCoverageTests`
/// lands; it stands alone until then, so the suite type carries its own name.)
@Suite("the real autoencoder's 238 tensors are the tree's parameters, or named as unreachable")
struct VAEWeightKeyCoverageTests {
    static let file = "diffusion_pytorch_model.safetensors"
    static let publishedKeyCount = 238
    static let unreachableKeyCount = 12

    static func header() throws -> SafeTensorsHeader {
        let release = try #require(SnapshotUnderTest.qwenImage21.release)
        return try SafeTensorsHeader(contentsOf: release.appending(path: "vae/\(file)"))
    }

    @Test(
        "every published tensor is a parameter of the tree or a named unreachable one",
        .enabled(if: SnapshotUnderTest.qwenImage21.hasRelease))
    func namesMatch() throws {
        let (_, configuration) = try VAEFixture.publishedConfiguration()
        let published = Set(try Self.header().entries.map(\.name))
        #expect(published.count == Self.publishedKeyCount)

        let unreachable = published.filter {
            $0.contains(QwenImage21VAEWeights.temporalInfix)
        }
        #expect(unreachable.count == Self.unreachableKeyCount)

        let claimed = Set(
            QwenImage21Autoencoder(configuration).parameters().flattened().map(\.0))
        let absent = claimed.subtracting(published)
        let unclaimed = published.subtracting(claimed).subtracting(unreachable)
        #expect(
            absent.isEmpty, Comment(rawValue: "expected but absent: \(absent.sorted().prefix(8))"))
        #expect(
            unclaimed.isEmpty,
            Comment(rawValue: "present but unclaimed: \(unclaimed.sorted().prefix(8))"))
        #expect(claimed.count == Self.publishedKeyCount - Self.unreachableKeyCount)
    }

    @Test(
        "every parameter's shape, put back in the checkpoint's layout, is the file's",
        .enabled(if: SnapshotUnderTest.qwenImage21.hasRelease))
    func shapesMatch() throws {
        let (_, configuration) = try VAEFixture.publishedConfiguration()
        let published = try Self.header().entries.reduce(into: [String: [Int]]()) {
            $0[$1.name] = $1.shape
        }
        for (path, parameter) in QwenImage21Autoencoder(configuration).parameters().flattened() {
            #expect(
                QwenImage21VAEWeights.checkpointShape(of: path, parameter.shape)
                    == published[path], Comment(rawValue: path))
        }
    }

    @Test(
        "the published config is the one the port's widths are built from",
        .enabled(if: SnapshotUnderTest.qwenImage21.hasRelease))
    func configurationMatchesTheFile() throws {
        let (_, configuration) = try VAEFixture.publishedConfiguration()
        #expect(configuration.encoderStageDims == [96, 96, 192, 384, 768, 768])
        #expect(configuration.decoderStageDims == [1152, 1152, 1152, 576, 288, 144])
        #expect(configuration.temperalDownsample == [false, true, true, true])
        #expect(configuration.temperalUpsample == [true, true, true, false])
        #expect(configuration.spatialCompression == 16)
        #expect(configuration.zDim == 64)
        #expect(configuration.inChannels == 4 && configuration.outChannels == 4)
        #expect(configuration.isResidual)
    }

    @Test("the fixture's tensors go into the tree's layouts and come back to their own shapes")
    func layoutsRoundTrip() throws {
        let weights = VAEFixture.weights(try Fixture.load("vae"), under: "model.")
        let sanitized = QwenImage21VAEWeights.sanitized(weights)
        let dropped = weights.keys.filter {
            $0.contains(QwenImage21VAEWeights.temporalInfix)
        }
        #expect(dropped.count == 4, "the doll's house has two temporal convolutions")
        #expect(sanitized.count == weights.count - dropped.count)
        for (name, tensor) in sanitized {
            #expect(
                QwenImage21VAEWeights.checkpointShape(of: name, tensor.shape)
                    == weights[name]!.shape, Comment(rawValue: name))
        }
        // A kernel's channels move to the end, a gain flattens, a bias stays.
        #expect(sanitized["encoder.conv_in.weight"]?.shape == [8, 3, 3, 4])
        #expect(sanitized["decoder.up_blocks.0.upsampler.resample.1.weight"]?.shape == [24, 3, 3, 24])
        #expect(sanitized["decoder.mid_block.attentions.0.norm.gamma"]?.shape == [24])
        #expect(sanitized["decoder.norm_out.gamma"]?.shape == [12])
        #expect(sanitized["decoder.conv_out.bias"]?.shape == [4])
    }

    @Test("the doll's-house fixture covers the tree exactly, once the dead tensors are dropped")
    func fixtureCoversTheTree() throws {
        let sanitized = QwenImage21VAEWeights.sanitized(
            VAEFixture.weights(try Fixture.load("vae"), under: "model."))
        let tree = Set(
            QwenImage21Autoencoder(VAEFixture.dollsHouse).parameters().flattened().map(\.0))
        #expect(Set(sanitized.keys) == tree)
    }
}
