import Testing
import ZephraCore
import ZephraEngine

@testable import Zephra

/// Where the chosen model stands, and what the toolbar offers to press about it.
@Suite("the toolbar's load control")
struct ModelLoadStatusTests {
    private let chosen = ModelCatalog.zImageTurbo8bit
    private let other = ModelCatalog.zImageTurbo4bit

    private func status(
        state: EngineState = .idle,
        loaded: ModelDescriptor? = nil,
        residency: WeightResidency? = nil
    ) -> ModelLoadStatus {
        ModelLoadStatus.status(of: chosen, state: state, loaded: loaded, residency: residency)
    }

    @Test("offers Load when nothing is loaded")
    func offersLoad() {
        let status = status()
        #expect(status == .notLoaded)
        #expect(status.word == nil)
        #expect(status.buttonTitle == "Load")
        #expect(status.pressLoads)
    }

    @Test("offers Unload once the chosen model is in")
    func offersUnload() {
        let status = status(state: .ready, loaded: chosen, residency: .resident)
        #expect(status == .loaded(streamed: false))
        #expect(status.word == "Loaded")
        #expect(status.buttonTitle == "Unload")
        #expect(!status.pressLoads)
    }

    @Test("says Streaming when the loaded weights are read from the disk")
    func saysStreaming() {
        let status = status(state: .ready, loaded: chosen, residency: .streamed)
        #expect(status.word == "Streaming")
        #expect(status.help(chosen: chosen, loaded: chosen).contains("read from the disk"))
    }

    @Test("offers Try Again after a failure")
    func offersTryAgain() {
        let status = status(state: .failed(.noBackend(.zImage)))
        #expect(status == .failed)
        #expect(status.buttonTitle == "Try Again")
        #expect(status.word == "Failed")
    }

    @Test("says what unloading costs when another model is the one in memory")
    func namesTheModelThatGoesFirst() {
        let status = status(state: .ready, loaded: other, residency: .resident)
        #expect(status == .notLoaded)
        let help = status.help(chosen: chosen, loaded: other)
        #expect(help == "Loads \(chosen.fullName). Unloads \(other.fullName) first.")
    }

    @Test("offers nothing to press while the model is on its way in")
    func offersNothingMidFlight() {
        #expect(status(state: .loading(.preparing)).buttonTitle == nil)
        #expect(status(state: .loading(.preparing)).word == "Loading\u{2026}")
        #expect(status(state: .building(BuildProgressEvent(
            component: "transformer", completedComponents: 0, totalComponents: 2, fraction: 0.4
        ))).word == "Building")
        #expect(status(state: .downloading(DownloadProgressEvent(
            completedFiles: 1, totalFiles: 4, fraction: 0.2, bytesPerSecond: nil
        ))).word == "Downloading")
    }
}
