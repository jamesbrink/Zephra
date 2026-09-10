import Foundation
import ZephraTestSupport

extension SnapshotUnderTest {
    /// The `mlx-community/ltx-2.5-mlx` release on this Mac, or the variant packed from it, for the
    /// tests that read the real tokenizer or the shard headers. `LTX2_SNAPSHOT` names one
    /// somewhere else (`TEST_RUNNER_LTX2_SNAPSHOT` under `xcodebuild test`).
    static let ltx2 = SnapshotUnderTest(
        repository: "mlx-community/ltx-2.5-mlx", environmentVariable: "LTX2_SNAPSHOT")

    /// Whether the release on this Mac holds the video encoder. A pack fetched before a first
    /// frame could be held has every other file and not this one, so the suite that reads its
    /// header gates on the file rather than on `hasRelease`.
    var hasEncoderFile: Bool {
        guard let release else { return false }
        return FileManager.default.fileExists(
            atPath: release.appending(path: "vae_encoder.safetensors").path(percentEncoded: false))
    }

    /// Whether the release on this Mac holds the spatial latent upsampler. It is the second
    /// stage's file alone, fetched after the five the first stage runs on, so a pack can have
    /// everything else and not it; the suite that reads its header gates on the file.
    var hasUpsamplerFile: Bool {
        guard let release else { return false }
        return FileManager.default.fileExists(
            atPath: release.appending(path: "spatial_upscaler_x2_v1_1.safetensors").path(percentEncoded: false))
    }

    /// Where the tokenizer files are in whichever layout was found: the release keeps them
    /// beside Gemma's weights in `gemma4-12b-ltx-v1/`, the packed variant under `text_encoder/`.
    var ltx2TokenizerDirectory: URL? {
        guard let directory else { return nil }
        return ["gemma4-12b-ltx-v1", "text_encoder"].map { directory.appending(path: $0) }
            .first { FileManager.default.fileExists(atPath: $0.appending(path: "tokenizer.json").path(percentEncoded: false)) }
    }
}
