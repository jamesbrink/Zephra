import ZephraTestSupport

extension SnapshotUnderTest {
    /// The FLUX.2 klein 4B release on this Mac, or either variant packed from it, for the tests
    /// that read published configs or tokenizer files. `FLUX2_KLEIN_SNAPSHOT` names one
    /// somewhere else.
    static let flux2Klein = SnapshotUnderTest(
        repository: "black-forest-labs/FLUX.2-klein-4B", environmentVariable: "FLUX2_KLEIN_SNAPSHOT")
}
