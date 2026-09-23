import Foundation
import ZephraTestSupport

extension SnapshotUnderTest {
    /// The Qwen-Image 2.1 release on this Mac, for the one suite here that reads a published
    /// config rather than inventing one.
    ///
    /// The same declaration the kit's suites use, written out again because a test target
    /// exports nothing. `QWEN_IMAGE_21_SNAPSHOT` names a directory outright — under
    /// `xcodebuild test` spell it `TEST_RUNNER_QWEN_IMAGE_21_SNAPSHOT`.
    static let qwenImage21 = SnapshotUnderTest(
        repository: "Qwen/Qwen-Image-2.1",
        environmentVariable: "QWEN_IMAGE_21_SNAPSHOT",
        alsoLookIn: [URL(filePath: "/Volumes/ExternalStorage/Models/Qwen-Image-2.1")])
}
