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

        #expect(witness.asked.map(\.offset) == [0, 100, 200, 300])
        #expect(witness.asked.allSatisfy { $0.limit == LinkClient.libraryPageSize })
        #expect(
            witness.asked.map(\.held) == [0, 100, 200, 300],
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
        #expect(bed.host.commands.filter(Self.isPage).count == 2, "the refusal, then the page")
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
        #expect(bed.host.commands.filter(Self.isPage).count == 1)
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
        try await settle { bed.client.library.count == 2 }

        #expect(bed.client.library.map(\.fileName).sorted() == ["one.png", "two.png"])
        #expect(bed.client.libraryIsComplete)
    }

    @Test("a frozen client is complete the moment it is made")
    func aFrozenClientIsComplete() {
        let client = LinkClient.frozen(
            snapshot: ClientFixtures.snapshot, library: [ClientFixtures.entry("one.png")])
        #expect(client.libraryIsComplete)
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
