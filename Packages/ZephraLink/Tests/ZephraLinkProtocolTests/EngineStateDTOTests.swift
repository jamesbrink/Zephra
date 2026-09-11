import Foundation
import Testing
import ZephraCore
import ZephraEngine
@testable import ZephraLinkProtocol

@Suite("The engine's state flattens to scalars without losing what the phone draws")
struct EngineStateDTOTests {
    @Test("Every case of the engine's state has a case here")
    func everyCaseIsCovered() throws {
        let states: [EngineState] = [
            .idle,
            .checkingModel,
            .downloading(DownloadProgressEvent(completedFiles: 1, totalFiles: 4, fraction: 0.25)),
            .building(BuildProgressEvent(
                component: "transformer", completedComponents: 1, totalComponents: 3,
                fraction: 0.3)),
            .loading(.preparing),
            .warmingUp,
            .ready,
            .generating(GenerationProgressEvent(phase: .denoising(step: 2, of: 9), fraction: 0.2)),
            .upscaling(UpscaleProgressEvent(completedTiles: 2, totalTiles: 8)),
            .cancelling,
            .failed(.noBackend(BackendID(rawValue: "nowhere"))),
        ]
        #expect(Set(states.map { EngineStateDTO($0).kind }).count == EngineStateDTO.Kind.allCases.count)
        for state in states {
            #expect(try LinkFixtures.roundTrip(EngineStateDTO(state)) == EngineStateDTO(state))
        }
    }

    @Test("A denoising step carries its place and its pace")
    func denoisingCarriesItsNumbers() {
        let dto = EngineStateDTO(
            .generating(GenerationProgressEvent(
                phase: .denoising(step: 3, of: 9), fraction: 0.33, secondsPerStep: 1.5)))
        #expect(dto.step == 3)
        #expect(dto.steps == 9)
        #expect(dto.secondsPerStep == 1.5)
        #expect(dto.phase == "Denoising")
        #expect(!dto.isFinishing)
        #expect(dto.isBusy)
    }

    @Test("Decoding and saving read as finishing, so the phone need not know the rule")
    func finishingIsCarried() {
        for phase in [GenerationPhase.decoding, .saving] {
            let dto = EngineStateDTO(.generating(GenerationProgressEvent(phase: phase, fraction: 1)))
            #expect(dto.isFinishing)
            #expect(dto.step == nil)
        }
    }

    @Test("A preview frame never rides inside a state update")
    func previewIsNeverInTheState() throws {
        let preview = GenerationPreview(
            width: 2, height: 2, pixels: Data(repeating: 0xFF, count: 16))
        let dto = EngineStateDTO(
            .generating(GenerationProgressEvent(
                phase: .denoising(step: 1, of: 4), fraction: 0.25, preview: preview)))
        let json = String(decoding: try LinkJSON.encode(dto), as: UTF8.self)
        #expect(!json.contains("pixels"))
        #expect(json.count < 400)
    }

    @Test("A failure carries the words the Mac would have shown")
    func failureCarriesItsMessage() {
        let error = EngineError.noBackend(BackendID(rawValue: "nowhere"))
        let dto = EngineStateDTO(.failed(error))
        #expect(dto.message == error.message)
        #expect(!dto.isBusy)
        #expect(!dto.acceptsGeneration)
    }

    @Test("Ready is the one state that takes a generation")
    func readyAcceptsWork() {
        #expect(EngineStateDTO(.ready).acceptsGeneration)
        #expect(!EngineStateDTO(.idle).acceptsGeneration)
        #expect(!EngineStateDTO(.cancelling).acceptsGeneration)
    }

    @Test("A download's bytes and files come across")
    func downloadCarriesItsNumbers() {
        let dto = EngineStateDTO(
            .downloading(DownloadProgressEvent(
                completedFiles: 2, totalFiles: 5, fraction: 0.4, bytesPerSecond: 1_000,
                completedBytes: 400, totalBytes: 1_000)))
        #expect(dto.completedFiles == 2)
        #expect(dto.totalFiles == 5)
        #expect(dto.completedBytes == 400)
        #expect(dto.totalBytes == 1_000)
        #expect(dto.bytesPerSecond == 1_000)
    }
}
