import Foundation
import Testing
import ZephraLinkProtocol

@testable import ZephraMobile

/// What the phone says about the model a Mac has in memory, and the way back from a lost run.
///
/// Every answer here is read off the state the Mac sent. The model chosen and the model loaded
/// are two fields now, and the whole point of the second one is that the phone stops guessing
/// the first means the second — so these are sentences about a DTO, not about a screen.
@Suite("What the phone says about the model a Mac has loaded")
struct ModelLoadingTests {
    @Test("Try Again appears only on a failure, and only where the Mac takes the command")
    func tryAgainIsShownOnlyWhereItWorks() {
        #expect(TryAgainButton.isShown(supportsModelLoading: true, kind: .failed))
        #expect(
            !TryAgainButton.isShown(supportsModelLoading: false, kind: .failed),
            "an older Mac has no such command; Generate alone is the way back there")
        for kind in EngineStateDTO.Kind.allCases where kind != .failed {
            #expect(
                !TryAgainButton.isShown(supportsModelLoading: true, kind: kind),
                "there is nothing to come back from in \(kind.rawValue)")
        }
        #expect(
            !TryAgainButton.isShown(supportsModelLoading: true, kind: nil),
            "and a Mac that has said nothing yet")
    }

    @Test("A Mac with nothing in memory says so beside the model's name")
    func nothingLoadedIsSaid() {
        let idle = EngineStateDTO(kind: .idle, modelID: "klein", loadedModelID: nil)
        #expect(ModelLoadWord.label("klein 4-bit", modelID: "klein", engine: idle)
            == "klein 4-bit \u{00B7} Not loaded")

        let loaded = EngineStateDTO(kind: .ready, modelID: "klein", loadedModelID: "klein")
        #expect(ModelLoadWord.label("klein 4-bit", modelID: "klein", engine: loaded) == "klein 4-bit")
        #expect(
            ModelLoadWord.label("klein 4-bit", modelID: "klein", engine: nil) == "klein 4-bit",
            "a Mac that has said nothing is not a Mac with nothing loaded")
    }

    @Test("The picker marks the row whose weights are in, and only that row")
    func theLoadedRowIsMarked() {
        let engine = EngineStateDTO(kind: .ready, modelID: "klein", loadedModelID: "klein")
        #expect(ModelLoadWord.marker(for: "klein", engine: engine) == "Loaded")
        #expect(ModelLoadWord.marker(for: "wan", engine: engine) == nil)
        #expect(ModelLoadWord.marker(for: "klein", engine: nil) == nil)
        let empty = EngineStateDTO(kind: .idle, modelID: "klein", loadedModelID: nil)
        #expect(
            ModelLoadWord.marker(for: "klein", engine: empty) == nil,
            "the model chosen is not the model loaded")
    }

    @Test("The line under Generate says what the press does first")
    func generateSaysWhatItLoads() {
        let idle = EngineStateDTO(kind: .idle, modelID: "klein", loadedModelID: nil)
        let here = AvailabilityDTO(
            kind: .available, bytes: nil, reason: nil, label: "Downloaded", needsNetwork: false,
            isObtainable: true)
        #expect(
            ModelLoadNote.text(name: "klein 4-bit", modelID: "klein", engine: idle, availability: here)
                == "Loads klein 4-bit first")

        let toFetch = AvailabilityDTO(
            kind: .needsDownload, bytes: 24_000_000_000, reason: nil, label: "24 GB download",
            needsNetwork: true, isObtainable: true)
        #expect(
            ModelLoadNote.text(name: "Wan 2.2", modelID: "klein", engine: idle, availability: toFetch)
                == "Downloads 24 GB for Wan 2.2 first")

        let toBuild = AvailabilityDTO(
            kind: .needsBuild, bytes: nil, reason: nil, label: "Builds on first use",
            needsNetwork: false, isObtainable: true)
        #expect(
            ModelLoadNote.text(name: "klein 4-bit", modelID: "klein", engine: idle, availability: toBuild)
                == "Builds klein 4-bit first")
    }

    @Test("A press over weights already in promises nothing")
    func aLoadedModelPromisesNothing() {
        let loaded = EngineStateDTO(kind: .ready, modelID: "klein", loadedModelID: "klein")
        #expect(
            ModelLoadNote.text(name: "klein 4-bit", modelID: "klein", engine: loaded, availability: nil)
                == nil)
        #expect(
            ModelLoadNote.text(name: "klein 4-bit", modelID: "klein", engine: nil, availability: nil)
                == nil,
            "and a Mac that has said nothing promises nothing either")
    }
}
