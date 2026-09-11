import Foundation

/// The three filesystem calls behind the four properties above.
///
/// Kept apart so `LinkFileStore` reads as what it stores rather than as permission arithmetic.
/// Every write goes to a hidden sibling created at 0600 and is renamed over the real name, so a
/// reader never sees half a list and the bytes are never briefly world-readable; the folder
/// itself is made at 0700, since it is the folder rather than the file that keeps another
/// account out of a name it can guess.
extension LinkFileStore {
    /// What one file holds, or nil when there is no such file.
    func read(_ name: String) throws -> Data? {
        do {
            return try Data(contentsOf: folder.appending(path: name))
        } catch CocoaError.fileReadNoSuchFile {
            return nil
        }
    }

    /// Puts bytes in one file, atomically, and only this user may read them.
    func write(_ bytes: Data, to name: String) throws {
        let files = FileManager.default
        try files.createDirectory(
            at: folder,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        let destination = folder.appending(path: name).path(percentEncoded: false)
        let temporary = folder.appending(path: ".\(name).partial").path(percentEncoded: false)
        try? files.removeItem(atPath: temporary)
        guard files.createFile(
            atPath: temporary, contents: bytes, attributes: [.posixPermissions: 0o600])
        else { throw LinkFileFailure(path: temporary, code: errno) }
        // `rename` rather than remove-then-move: the destination is replaced in one step, so a
        // launch that lands between the two never finds the file missing.
        guard rename(temporary, destination) == 0 else {
            try? files.removeItem(atPath: temporary)
            throw LinkFileFailure(path: destination, code: errno)
        }
    }
}

/// A write of a link secret that did not work, with the code it gave.
///
/// Carried rather than swallowed, for the same reason `LinkKeychainFailure` is: a folder that
/// cannot be written is not a Mac with no pairings.
struct LinkFileFailure: Error, LocalizedError {
    /// What was being written.
    let path: String
    /// The `errno` the call left behind.
    let code: Int32

    var errorDescription: String? {
        "The companion's secrets could not be written to \(path): \(String(cString: strerror(code)))"
    }
}
