import Foundation
import Testing

@testable import ZephraEngine

@Suite("Library writes keep external volume ownership")
@MainActor
struct ImageLibraryMountedWriteTests {
    @Test("saving and mutations never recreate an unmounted external disk")
    func absentVolume() throws {
        let root = URL(filePath: "/Volumes/ZephraMissingDisk-\(UUID().uuidString)/Images")
        let library = ImageLibrary(root: root)
        let picture = LibraryAnnotationTests.image(seed: 90)
        #expect(throws: ImageDirectoryError.self) { try library.write(picture) }
        #expect(throws: ImageDirectoryError.self) { try library.writeAlbums([Album(name: "Ports")]) }
        let absentImage = root.appending(path: "missing.png")
        #expect(throws: ImageDirectoryError.self) { try library.moveToRecentlyDeleted(absentImage) }
        #expect(throws: ImageDirectoryError.self) { try library.restoreFromRecentlyDeleted(absentImage) }
        #expect(!FileManager.default.fileExists(atPath: root.deletingLastPathComponent().path))
    }
}
