import Foundation
import Testing
import ZephraLinkHost
import ZephraLinkProtocol
import ZephraTestSupport

@testable import Zephra

/// The secrets a build signed ad hoc keeps, which is every build made on this Mac.
@Suite("The link's file store keeps the identity and the pairings where no prompt can reach them")
struct LinkFileStoreTests {
    /// A paired phone to write down, made from a throwaway identity's public half.
    private func device(name: String, lastSeen: Date? = nil) -> PairedDevice {
        PairedDevice(
            keys: DeviceIdentity().publicKeys, name: name, pairedAt: Date(timeIntervalSince1970: 1),
            lastSeen: lastSeen)
    }

    @Test("the identity it hands back is the one it was given, and it is made once")
    func theIdentityRoundTrips() throws {
        let scratch = Scratch("LinkFileStore")
        let store = LinkFileStore(folder: scratch.root.appending(path: "Companion"))
        #expect(try store.identityBytes() == nil)
        let made = try store.identity()
        #expect(try store.identityBytes()?.count == DeviceIdentity.rawByteCount)
        #expect(try store.identity().rawRepresentation == made.rawRepresentation)
    }

    @Test("a device list survives a write and a read, and an empty folder is no devices")
    func devicesRoundTrip() throws {
        let scratch = Scratch("LinkFileStore")
        let store = LinkFileStore(folder: scratch.root.appending(path: "Companion"))
        #expect(try store.load().isEmpty)
        let devices = [device(name: "James's iPhone"), device(name: "The iPad")]
        try store.save(devices)
        #expect(try store.load() == devices)
        try store.save([devices[0]])
        #expect(try store.load() == [devices[0]])
    }

    @Test("the folder is this user's alone and so is every file in it")
    func onlyThisUserMayRead() throws {
        let scratch = Scratch("LinkFileStore")
        let folder = scratch.root.appending(path: "Companion")
        let store = LinkFileStore(folder: folder)
        _ = try store.identity()
        try store.save([device(name: "James's iPhone")])
        let files = FileManager.default
        func mode(_ url: URL) throws -> Int? {
            try files.attributesOfItem(atPath: url.path(percentEncoded: false))[.posixPermissions]
                as? Int
        }
        #expect(try mode(folder) == 0o700)
        #expect(try mode(folder.appending(path: LinkFileStore.identityFile)) == 0o600)
        #expect(try mode(folder.appending(path: LinkFileStore.devicesFile)) == 0o600)
        // Nothing half-written is left behind for a scan or a backup to find.
        let left = try files.contentsOfDirectory(atPath: folder.path(percentEncoded: false))
        #expect(left.sorted() == [LinkFileStore.devicesFile, LinkFileStore.identityFile])
    }

    @Test("forgetting everything leaves a folder that looks like a Mac that has never linked")
    func removeAllForgetsBoth() throws {
        let scratch = Scratch("LinkFileStore")
        let store = LinkFileStore(folder: scratch.root.appending(path: "Companion"))
        _ = try store.identity()
        try store.save([device(name: "James's iPhone")])
        try store.removeAll()
        #expect(try store.identityBytes() == nil)
        #expect(try store.load().isEmpty)
        // Twice is not a failure: there is nothing to take away the second time.
        try store.removeAll()
    }

    @Test("a fresh start keeps its secrets under its own throwaway root")
    func aFreshStartIsItsOwnFolder() {
        let fresh = FreshStart(root: URL(filePath: "/tmp/zephra-fresh", directoryHint: .isDirectory))
        #expect(
            LinkFileStore(freshStart: fresh).folder.path(percentEncoded: false)
                == "/tmp/zephra-fresh/Companion/")
        #expect(
            LinkFileStore(freshStart: nil).folder.path(percentEncoded: false)
                == URL.applicationSupportDirectory
                    .appending(path: "Zephra/Companion", directoryHint: .isDirectory)
                    .path(percentEncoded: false))
    }
}
