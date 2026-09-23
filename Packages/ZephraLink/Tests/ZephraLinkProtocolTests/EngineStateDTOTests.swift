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

    @Test("Whether another may be queued is carried, and survives the trip")
    func queueingIsCarried() throws {
        var dto = EngineStateDTO(
            .generating(GenerationProgressEvent(phase: .denoising(step: 1, of: 9), fraction: 0.1)))
        #expect(!dto.canQueue, "the state alone knows only that the engine is not idle")
        dto.canQueue = true
        let read = try LinkFixtures.roundTrip(dto)
        #expect(read.canQueue, "what the host stamps is what the phone reads")
        #expect(!read.acceptsGeneration, "and it is not the same fact")
    }

    @Test("A Mac too old to have an opinion reads as one picture at a time")
    func anOlderMacReadsAsOneAtATime() throws {
        let older = #"{"kind":"ready","isBusy":false,"isFinishing":false,"acceptsGeneration":true}"#
        let ready = try LinkJSON.decode(EngineStateDTO.self, from: Data(older.utf8))
        #expect(ready.canQueue, "a Mac that takes a generation takes this one")

        let busy = #"{"kind":"generating","isBusy":true,"isFinishing":false,"acceptsGeneration":false}"#
        let running = try LinkJSON.decode(EngineStateDTO.self, from: Data(busy.utf8))
        #expect(!running.canQueue, "and one already rendering takes nothing behind it")
    }

    @Test("Which model is loaded is its own fact, and survives the trip")
    func loadedModelIsCarried() throws {
        var dto = EngineStateDTO(.ready, modelID: "flux2-klein-4b-4bit")
        #expect(dto.loadedModelID == nil, "the state alone does not know it")
        #expect(try LinkFixtures.roundTrip(dto).loadedModelID == nil,
                "and a Mac that says nothing is loaded is read as saying exactly that")

        dto.loadedModelID = "z-image-turbo-8bit"
        let read = try LinkFixtures.roundTrip(dto)
        #expect(read.loadedModelID == "z-image-turbo-8bit")
        #expect(read.modelID == "flux2-klein-4b-4bit", "the chosen model is the other fact")
    }

    @Test("A Mac that says nothing about it is read the way that Mac meant it")
    func anOlderMacsLoadedModel() throws {
        // Every Mac before this loaded whatever it had chosen, so `.idle` meant nothing was
        // loaded and every other case meant the chosen model was.
        let idle = #"{"kind":"idle","modelID":"z","isBusy":false,"isFinishing":false,"acceptsGeneration":false}"#
        #expect(try LinkJSON.decode(EngineStateDTO.self, from: Data(idle.utf8)).loadedModelID == nil)

        let ready = #"{"kind":"ready","modelID":"z","isBusy":false,"isFinishing":false,"acceptsGeneration":true}"#
        #expect(
            try LinkJSON.decode(EngineStateDTO.self, from: Data(ready.utf8)).loadedModelID == "z")

        // A Mac that has the field and nothing loaded writes it as null, which is not the same
        // answer and must not be read as one.
        let onDemand = #"{"kind":"ready","modelID":"z","loadedModelID":null,"isBusy":false,"isFinishing":false,"acceptsGeneration":true}"#
        #expect(
            try LinkJSON.decode(EngineStateDTO.self, from: Data(onDemand.utf8)).loadedModelID
                == nil)
    }

    @Test("Every field is written, so one added later cannot be silently left out")
    func everyFieldSurvivesTheTrip() throws {
        // `encode(to:)` is written by hand — the one way to say "nothing is loaded" and mean it
        // — so a field added later compiles and is never sent unless something checks them all
        // at once. Every value here is deliberately not the default for its type.
        let full = EngineStateDTO(
            kind: .generating, phase: "Denoising", step: 3, steps: 9, fraction: 0.33,
            secondsPerStep: 1.5, completedBytes: 400, totalBytes: 1_000, completedFiles: 2,
            totalFiles: 5, bytesPerSecond: 1_000, component: "transformer",
            completedComponents: 1, totalComponents: 3, completedTiles: 2, totalTiles: 8,
            modelID: "flux2-klein-4b-4bit", message: "the GPU stopped responding",
            loadedModelID: "z-image-turbo-8bit", isBusy: true, isFinishing: true,
            acceptsGeneration: true, canQueue: true)

        #expect(try LinkFixtures.roundTrip(full) == full)

        // And every one of them is actually in the JSON, rather than surviving by both ends
        // defaulting the same way.
        let json = String(decoding: try LinkJSON.encode(full), as: UTF8.self)
        let mirror = Mirror(reflecting: full)
        #expect(mirror.children.count == 23, "a field was added; add it to `full` as well")
        for child in mirror.children {
            let name = try #require(child.label)
            #expect(json.contains("\"\(name)\":"), "\(name) is never written")
        }
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
