import ZephraTestSupport

extension SnapshotUnderTest {
    /// The Qwen-Image-2512 release on this Mac, or the 4-bit variant packed from it, for the
    /// tests that read published configs or tokenizer files. `QWEN_IMAGE_SNAPSHOT` names one
    /// somewhere else.
    static let qwenImage = SnapshotUnderTest(
        repository: "Qwen/Qwen-Image-2512", environmentVariable: "QWEN_IMAGE_SNAPSHOT")
}
