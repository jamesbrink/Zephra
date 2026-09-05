import Foundation

/// An original's identity and a bounded-memory byte comparison for its copies.
struct ImageMigrationFile {
    let url: URL
    let path: String
    let bytes: Int64
    private let identity: [FileAttributeKey: NSObject]

    init(url: URL, path: String) throws {
        self.url = url
        self.path = path
        identity = try Self.attributes(url)
        bytes = (identity[.size] as? NSNumber)?.int64Value ?? 0
    }

    static func attributes(_ url: URL) throws -> [FileAttributeKey: NSObject] {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular else {
            throw ImageDirectoryError("Cannot move a linked or special image file: \(url.path).")
        }
        guard let size = attributes[.size] as? NSNumber,
              let modified = attributes[.modificationDate] as? NSDate,
              let inode = attributes[.systemFileNumber] as? NSNumber,
              let device = attributes[.systemNumber] as? NSNumber else {
            throw ImageDirectoryError("Cannot verify the identity of \(url.path).")
        }
        return [.size: size, .modificationDate: modified, .systemFileNumber: inode, .systemNumber: device]
    }

    func verify(at copy: URL) throws {
        guard try Self.attributes(url) == identity else {
            throw ImageDirectoryError("The original changed during the move: \(url.path).")
        }
        _ = try Self.attributes(copy)
        let original = try FileHandle(forReadingFrom: url)
        defer { try? original.close() }
        let copied = try FileHandle(forReadingFrom: copy)
        defer { try? copied.close() }
        while true {
            let left = try original.read(upToCount: 1024 * 1024) ?? Data()
            let right = try copied.read(upToCount: 1024 * 1024) ?? Data()
            guard left == right else { throw ImageDirectoryError("Verification failed for \(url.path).") }
            if left.isEmpty { break }
        }
        guard try Self.attributes(url) == identity else {
            throw ImageDirectoryError("The original changed during verification: \(url.path).")
        }
    }
}
