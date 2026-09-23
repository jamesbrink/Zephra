import Foundation
import ZephraTestSupport

extension SnapshotUnderTest {
    /// The Qwen-Image 2.1 release on this Mac, for the suites that read published configs or
    /// tokenizer files.
    ///
    /// `QWEN_IMAGE_21_SNAPSHOT` names one outright — under `xcodebuild test` spell it
    /// `TEST_RUNNER_QWEN_IMAGE_21_SNAPSHOT`. Otherwise the app's own models folder is looked
    /// in first, then the external volume this repository's Macs keep the big releases on,
    /// then the hub cache. The volume is named because 33 GB does not belong on a boot disk
    /// and a suite that skips on every machine is a suite nobody notices going quiet.
    static let qwenImage21 = SnapshotUnderTest(
        repository: "Qwen/Qwen-Image-2.1",
        environmentVariable: "QWEN_IMAGE_21_SNAPSHOT",
        alsoLookIn: [URL(filePath: "/Volumes/ExternalStorage/Models/Qwen-Image-2.1")])
}
