import Foundation
import Testing
import ZephraCore
import ZephraEngine
@testable import ZephraLinkProtocol

@Suite("The state the phone holds crosses without losing anything")
struct StateCodingTests {
    static let batch = UUID(uuidString: "1F4A2C88-6E51-4B2A-9C31-7D0E5F3A2B14")!
    static let row = UUID(uuidString: "3A7B9C10-2D4E-4F6A-8B5C-1E9D0A2B3C4D")!

    /// A snapshot with something in every field.
    static var snapshot: StateSnapshot {
        StateSnapshot(
            hostName: "halcyon",
            model: LinkFixtures.model,
            models: [LinkFixtures.model],
            engine: EngineStateDTO(.ready, modelID: LinkFixtures.model.id),
            queue: [LinkFixtures.queued(id: row, batchID: batch)],
            running: LinkFixtures.queued(id: row, batchID: batch),
            history: [HistoryEntry(id: row, fileName: "a.png", record: LinkFixtures.record)],
            availability: [LinkFixtures.model.id: AvailabilityDTO(.needsDownload(bytes: 4_000))],
            downloads: [DownloadDTO(
                id: "req", modelID: LinkFixtures.model.id, displayName: "Z-Image Turbo",
                status: .downloading, fraction: 0.5)],
            today: [RunSummary(
                id: batch, prompt: "a lighthouse", modelID: LinkFixtures.model.id, width: 1024,
                height: 1024, state: .finished, fileNames: ["a.png"], seedCount: 1,
                startedAt: LinkFixtures.date, finishedAt: LinkFixtures.date)],
            libraryCount: 412,
            acceptsWork: true)
    }

    @Test("A whole snapshot survives being written and read back")
    func snapshotRoundTrips() throws {
        #expect(try LinkFixtures.roundTrip(Self.snapshot) == Self.snapshot)
    }

    @Test("Whether the Mac can be told to load a model is advertised, and absent on an older one")
    func modelLoadingIsAdvertised() throws {
        var snapshot = Self.snapshot
        #expect(snapshot.modelLoading == nil, "a snapshot nobody stamped claims nothing")
        #expect(try LinkFixtures.roundTrip(snapshot).modelLoading == nil)

        snapshot.modelLoading = true
        #expect(try LinkFixtures.roundTrip(snapshot).modelLoading == true)
    }

    @Test("Every kind of delta survives being written and read back")
    func deltasRoundTrip() throws {
        let deltas: [StateDelta] = [
            .engine(EngineStateDTO(.ready)),
            .queue([LinkFixtures.queued(id: Self.row, batchID: Self.batch)]),
            .running(nil),
            .historyInserted(
                HistoryEntry(id: Self.row, fileName: "a.png", record: LinkFixtures.record)),
            .historyRemoved(Self.row),
            .model(LinkFixtures.model),
            .availability(["z": AvailabilityDTO(.available)]),
            .downloads([]),
            .today([]),
            .library(.upserted([LinkFixtures.entry])),
            .acceptsWork(false),
        ]
        #expect(deltas.count == StateDelta.Kind.allCases.count)
        for delta in deltas {
            let read = try LinkFixtures.roundTrip(delta)
            #expect(read == delta)
            #expect(read.kind == delta.kind)
        }
    }

    @Test("A delta's JSON is a tagged object whose shape does not move")
    func deltaJSONIsStable() throws {
        #expect(
            String(decoding: try LinkJSON.encode(StateDelta.acceptsWork(true)), as: UTF8.self)
                == #"{"kind":"acceptsWork","value":true}"#)
        #expect(
            String(decoding: try LinkJSON.encode(StateDelta.historyRemoved(Self.row)), as: UTF8.self)
                == #"{"kind":"historyRemoved","value":"3A7B9C10-2D4E-4F6A-8B5C-1E9D0A2B3C4D"}"#)
        #expect(
            String(decoding: try LinkJSON.encode(StateDelta.running(nil)), as: UTF8.self)
                == #"{"kind":"running","value":null}"#)
    }

    @Test("A library change says which of the three it is")
    func libraryChangeJSONIsStable() throws {
        #expect(
            String(decoding: try LinkJSON.encode(LibraryChange.removed(["a.png"])), as: UTF8.self)
                == #"{"kind":"removed","names":["a.png"]}"#)
        let reset = try LinkFixtures.roundTrip(LibraryChange.reset([LinkFixtures.entry], total: 9))
        guard case .reset(let entries, let total) = reset else {
            Issue.record("a reset read back as something else")
            return
        }
        #expect(entries == [LinkFixtures.entry])
        #expect(total == 9)
    }

    @Test("A preview frame carries its JPEG and where in the run it came from")
    func previewFrameRoundTrips() throws {
        let frame = PreviewFrameDTO(
            jpeg: Data([0xFF, 0xD8, 0xFF]), width: 256, height: 144, step: 3, steps: 9)
        #expect(try LinkFixtures.roundTrip(frame) == frame)
    }

    @Test("A library page keeps its window and its total")
    func libraryPageRoundTrips() throws {
        let page = LibraryPage(entries: [LinkFixtures.entry], offset: 40, total: 412)
        #expect(try LinkFixtures.roundTrip(page) == page)
    }
}
