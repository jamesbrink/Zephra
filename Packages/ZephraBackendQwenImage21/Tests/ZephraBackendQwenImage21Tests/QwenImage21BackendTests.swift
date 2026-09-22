import QwenImage21
import Testing
import ZephraCore
import ZephraTestSupport

@testable import ZephraBackendQwenImage21

@Suite("An idle 2.1 backend has loaded nothing and holds nothing")
struct QwenImage21BackendTests {
    @Test("a fresh backend names no model and no residency")
    func idleBackendHoldsNothing() {
        let backend = QwenImage21Backend()

        #expect(backend.loadedModelID == nil)
        // Nil rather than `.resident`: how the weights are held is what the last load did, and
        // a backend that has not loaded has not decided. The engine reads this to tell a
        // request for the same model the other way round from one already satisfied.
        #expect(backend.loadedResidency == nil)
    }

    @Test("this family serves Qwen-Image 2.1")
    func backendServesQwenImage21() {
        #expect(QwenImage21Backend.backendID == BackendID.qwenImage21)
        // The raw value is persisted in every descriptor and every saved picture's record, so
        // it is pinned rather than left to a rename.
        #expect(BackendID.qwenImage21.rawValue == "qwen-image-2.1")
    }

    @Test(
        "the size alignment the descriptor promises is the one the release asks for",
        .enabled(if: SnapshotUnderTest.qwenImage21.isPresent))
    func alignmentMatchesTheRelease() throws {
        // The pipeline throws `unalignedSize` for anything off its own grid and `clamp` is what
        // keeps a request on it, so the descriptor's number and the autoencoder's have to be
        // one number. This is where the interface's promise meets the published config.
        let snapshot = try #require(SnapshotUnderTest.qwenImage21.directory)
        let configuration = try QwenImage21Configuration(readingFrom: snapshot)

        #expect(QwenImage21ModelUnderTest.capabilities.sizeAlignment == configuration.sizeAlignment)
    }
}
