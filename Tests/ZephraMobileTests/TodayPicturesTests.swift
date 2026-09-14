import Foundation
import Testing
import ZephraLinkClient
import ZephraLinkProtocol

@testable import ZephraMobile

@MainActor
@Suite("Today opens the selected Mac's run")
struct TodayPicturesTests {
    @Test("Duplicate filenames on other Macs never enter the run's pager")
    func ownershipAndOrder() throws {
        let first = try host()
        let second = try host()
        defer { first.catalog.stop(); second.catalog.stop() }
        let run = try #require(second.client.snapshot?.today.first)
        let name = try #require(run.fileNames.last)
        let opened = try #require(second.catalog.entry(named: name))
        let pictures = TodayPictures.entries(around: opened, hosts: [first, second])

        #expect(pictures.map(\.fileName) == run.fileNames)
        #expect(pictures.allSatisfy { $0.hostID == second.id })
        #expect(pictures.count < second.catalog.entries.count)
        #expect(pictures.contains { $0.id == opened.id })
    }

    @Test("An opened picture survives its Mac or cache entry disappearing")
    func disappearingSource() throws {
        let host = try host()
        defer { host.catalog.stop() }
        let opened = try #require(host.catalog.entries.first)
        #expect(TodayPictures.entries(around: opened, hosts: []) == [opened])
        host.catalog.publish([])
        #expect(TodayPictures.entries(around: opened, hosts: [host]) == [opened])
    }

    @Test("Missing siblings are skipped and a clip opens in its own run")
    func partialCacheAndClip() throws {
        let host = try host()
        defer { host.catalog.stop() }
        let clip = try #require(host.catalog.entries.first(where: { $0.isVideo }))
        #expect(TodayPictures.entries(around: clip, hosts: [host]) == [clip])
        let picture = try #require(host.catalog.entries.first(where: { !$0.isVideo }))
        host.catalog.publish([picture, clip])
        #expect(TodayPictures.entries(around: picture, hosts: [host]) == [picture])
    }

    private func host() throws -> HostConnection {
        let snapshot = try #require(MobilePreview.snapshot())
        let client = LinkClient.frozen(snapshot: snapshot, library: MobilePreview.library())
        let preference = HostPreference(host: try #require(client.pairedHost))
        let catalog = LibraryCatalog(libraryRoot: nil, filesRoot: nil)
        catalog.hostID = preference.id
        catalog.publish(MobilePreview.library().map { CachedEntry($0) })
        return HostConnection(preference: preference, client: client, catalog: catalog, frozen: true)
    }
}
