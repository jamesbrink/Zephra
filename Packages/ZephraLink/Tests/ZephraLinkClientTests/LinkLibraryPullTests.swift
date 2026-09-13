import Foundation
import Testing
import ZephraLinkClient
import ZephraLinkProtocol

/// The phone reading the Mac's folder across after a connect.
///
/// The bug this pins: the Mac publishes library *changes*, so a phone that had just paired saw
/// nothing at all until somebody on the Mac made or edited a picture. Today was full and the
/// grid was empty.
@MainActor
@Suite("A phone pulls the Mac's library after every connect")
struct LinkLibraryPullTests {
    @Test("three hundred and fifty pictures arrive in four pages, each one visible before the next is asked for")
    func pagesFillTheLibraryAsTheyArrive() async throws {
        let bed = LinkClientUnderTest(remembering: DeviceIdentity())
        defer { Task { await bed.host.stop() } }
        bed.host.library = (0..<350).map { ClientFixtures.entry("picture-\($0).png") }
        await bed.client.connect()
        for _ in 0..<8 { await Task.yield() }
        let witness = PageWitness()
        bed.host.onCommand = { command in
            guard case .libraryPage(let offset, let limit) = command else { return }
            witness.record(offset: offset, limit: limit, held: bed.client.library.count)
        }

        try await bed.host.announce(ClientFixtures.snapshot, kind: .snapshot)
        try await settle { bed.client.libraryIsComplete }

        #expect(witness.asked.map(\.offset) == [0, 100, 200, 300, 0, 100, 200, 300])
        #expect(witness.asked.allSatisfy { $0.limit == LinkClient.libraryPageSize })
        #expect(
            witness.asked.map(\.held) == [0, 100, 200, 300, 350, 350, 350, 350],
            "each page is applied before the next is asked for, so the grid fills as they land")
        #expect(bed.client.library.count == 350)
        #expect(bed.client.library.first?.fileName == "picture-0.png")
        #expect(bed.client.library.last?.fileName == "picture-349.png")
        #expect(bed.client.libraryIsComplete)
    }

    @Test("a page the Mac refuses is asked for again, from the same offset")
    func aRefusedPageIsRetried() async throws {
        let bed = LinkClientUnderTest(remembering: DeviceIdentity())
        defer { Task { await bed.host.stop() } }
        bed.host.library = (0..<40).map { ClientFixtures.entry("picture-\($0).png") }
        bed.host.refusesPages = 1
        await bed.client.connect()
        for _ in 0..<8 { await Task.yield() }

        try await bed.host.announce(ClientFixtures.snapshot, kind: .snapshot)
        try await settle(within: .seconds(5)) { bed.client.libraryIsComplete }

        #expect(bed.client.library.count == 40)
        #expect(bed.host.commands.filter(Self.isPage).count == 3, "the refusal, then two matching legacy passes")
    }

    @Test("the library is empty and complete when the Mac's folder is")
    func anEmptyFolderIsACompleteListing() async throws {
        let bed = LinkClientUnderTest(remembering: DeviceIdentity())
        defer { Task { await bed.host.stop() } }
        await bed.client.connect()
        for _ in 0..<8 { await Task.yield() }

        try await bed.host.announce(ClientFixtures.snapshot, kind: .snapshot)
        try await settle { bed.client.libraryIsComplete }

        #expect(bed.client.library.isEmpty)
        #expect(bed.host.commands.filter(Self.isPage).count == 2)
    }

    @Test("a second snapshot pulls the folder again")
    func everyConnectPullsAgain() async throws {
        let bed = LinkClientUnderTest(remembering: DeviceIdentity())
        defer { Task { await bed.host.stop() } }
        bed.host.library = [ClientFixtures.entry("one.png")]
        await bed.client.connect()
        for _ in 0..<8 { await Task.yield() }
        try await bed.host.announce(ClientFixtures.snapshot, kind: .snapshot)
        try await settle { bed.client.libraryIsComplete }

        bed.host.library = [ClientFixtures.entry("two.png"), ClientFixtures.entry("one.png")]
        try await bed.host.announce(ClientFixtures.snapshot, kind: .snapshot)
        try await settle { bed.client.library.count == 2 && bed.client.libraryIsComplete }

        #expect(bed.client.library.map(\.fileName).sorted() == ["one.png", "two.png"])
        #expect(bed.client.libraryIsComplete)
    }

    @Test("a resync mid-pull carries the pull on rather than starting the library again")
    func aResyncCarriesThePullOn() async throws {
        let bed = LinkClientUnderTest(remembering: DeviceIdentity())
        defer { Task { await bed.host.stop() } }
        bed.host.library = (0..<350).map { ClientFixtures.entry("picture-\($0).png") }
        await bed.client.connect()
        for _ in 0..<8 { await Task.yield() }
        let witness = PageWitness()
        bed.host.onCommand = { command in
            guard case .libraryPage(let offset, let limit) = command else { return }
            witness.record(offset: offset, limit: limit, held: bed.client.library.count)
            // A gap in the stream costs a resync, which the Mac answers with a fresh snapshot
            // over the very folder this pull is reading.
            guard offset == 100 else { return }
            Task { try? await bed.host.announce(Self.snapshot(counting: 350), kind: .snapshot) }
        }

        try await bed.host.announce(Self.snapshot(counting: 350), kind: .snapshot)
        try await settle { bed.client.libraryIsComplete }

        #expect(
            witness.asked.map(\.offset) == [0, 100, 200, 300, 0, 100, 200, 300],
            "the second snapshot left the pull where it was rather than sending it back to 0")
        #expect(bed.client.library.count == 350)
    }

    @Test("a snapshot over a folder that has changed starts the library again")
    func aChangedCountStartsAgain() async throws {
        let bed = LinkClientUnderTest(remembering: DeviceIdentity())
        defer { Task { await bed.host.stop() } }
        bed.host.library = (0..<350).map { ClientFixtures.entry("picture-\($0).png") }
        await bed.client.connect()
        for _ in 0..<8 { await Task.yield() }
        let witness = PageWitness()
        bed.host.onCommand = { command in
            guard case .libraryPage(let offset, let limit) = command else { return }
            witness.record(offset: offset, limit: limit, held: bed.client.library.count)
            // Once, at the same point as the test above it: the pull that starts again asks
            // for offset 100 too, and announcing on every one of those would never end.
            guard offset == 100, witness.asked.filter({ $0.offset == 100 }).count == 1
            else { return }
            Task { try? await bed.host.announce(Self.snapshot(counting: 351), kind: .snapshot) }
        }

        try await bed.host.announce(Self.snapshot(counting: 350), kind: .snapshot)
        try await settle { bed.client.libraryIsComplete }

        #expect(
            witness.asked.map(\.offset).filter { $0 == 0 }.count == 3,
            "a count that moved is a folder to read again from the top")
        #expect(bed.client.library.count == 350)
    }

    @Test("A same-count replacement during legacy paging requires a new stable pass")
    func sameCountReplacement() async throws {
        let bed = LinkClientUnderTest(remembering: DeviceIdentity())
        defer { Task { await bed.host.stop() } }
        bed.host.library = (0..<150).map { ClientFixtures.entry("picture-\($0).png") }
        await bed.client.connect()
        for _ in 0..<8 { await Task.yield() }
        var replaced = false
        bed.host.onCommand = { command in
            guard case .libraryPage(let offset, _) = command, offset == 100, !replaced else { return }
            replaced = true
            bed.host.library[0] = ClientFixtures.entry("replacement.png")
        }
        try await bed.host.announce(Self.snapshot(counting: 150), kind: .snapshot)
        try await settle { bed.client.libraryIsComplete }
        #expect(replaced)
        #expect(bed.client.library == bed.host.library)
        #expect(!bed.client.library.contains { $0.fileName == "picture-0.png" })
    }

    @Test("a frozen client is complete the moment it is made")
    func aFrozenClientIsComplete() {
        let client = LinkClient.frozen(
            snapshot: ClientFixtures.snapshot, library: [ClientFixtures.entry("one.png")])
        #expect(client.libraryIsComplete)
    }

    /// The fixture's snapshot, saying the Mac's folder holds this many.
    private static func snapshot(counting entries: Int) -> StateSnapshot {
        var snapshot = ClientFixtures.snapshot
        snapshot.libraryCount = entries
        return snapshot
    }

    private static func isPage(_ command: Command) -> Bool {
        if case .libraryPage = command { return true }
        return false
    }

    /// Waits for the phone to have caught up, or gives up.
    private func settle(
        within limit: Duration = .seconds(2), _ until: @MainActor () -> Bool
    ) async throws {
        let deadline = ContinuousClock.now + limit
        while ContinuousClock.now < deadline {
            if until() { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(until(), "the phone never caught up")
    }
}

/// What the Mac was asked for, and what the phone was holding when it asked.
///
/// A class because the fake Mac keeps the closure that writes it, and the test reads it after.
@MainActor
final class PageWitness {
    private(set) var asked: [(offset: Int, limit: Int, held: Int)] = []

    func record(offset: Int, limit: Int, held: Int) {
        asked.append((offset: offset, limit: limit, held: held))
    }
}
