import Foundation
import Testing
import ZephraLinkProtocol
@testable import ZephraMobile

@Suite("Viewer actions use only the current file")
struct ViewerFileTests {
    @Test @MainActor func rejectsPreviousPageAndVersion() {
        let a = LibraryFixtures.cached("a.png")
        let b = LibraryFixtures.cached("b.png")
        let url = URL(filePath: "/a.png")
        let loaded = ViewerFile(entry: a, file: url)
        #expect(loaded.url(for: a) == url)
        #expect(loaded.url(for: b) == nil)
        let edited = LibraryFixtures.cached("a.png", fileSize: 2_000_000)
        #expect(loaded.url(for: edited) == nil)
        #expect(loaded.url(for: a.annotated(favourite: true)) == url)
    }

    @Test @MainActor func rejectsSameNameFromAnotherMac() {
        let entry = LibraryFixtures.template
        let a = CachedEntry(entry, hostID: HostID(keys: DeviceIdentity().publicKeys))
        let b = CachedEntry(entry, hostID: HostID(keys: DeviceIdentity().publicKeys))
        #expect(ViewerFile(entry: a, file: URL(filePath: "/a.png")).url(for: b) == nil)
    }
}
