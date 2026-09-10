import Foundation
import ZephraTestSupport

extension SnapshotUnderTest {
    /// The `FastVideo/FastWan2.2-TI2V-5B-FullAttn-Diffusers` release on this Mac, or the variant
    /// packed from it, for the tests that read the real tokenizer or the shard headers.
    /// `WAN_SNAPSHOT` names one somewhere else (`TEST_RUNNER_WAN_SNAPSHOT` under
    /// `xcodebuild test`).
    static let wan = SnapshotUnderTest(
        repository: "FastVideo/FastWan2.2-TI2V-5B-FullAttn-Diffusers", environmentVariable: "WAN_SNAPSHOT")

    /// Where the tokenizer files are in whichever layout was found: the release keeps them
    /// under `tokenizer/`, the packed variant under `text_encoder/`.
    var wanTokenizerDirectory: URL? {
        guard let directory else { return nil }
        return ["tokenizer", "text_encoder"].map { directory.appending(path: $0) }
            .first { FileManager.default.fileExists(atPath: $0.appending(path: "tokenizer.json").path(percentEncoded: false)) }
    }
}
