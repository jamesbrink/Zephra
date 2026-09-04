import Foundation

/// A checked inventory of regular files; traversal errors and links are never skipped.
struct ModelFileTree {
    let root: URL
    let files: [String: Int64]
    let folders: [String]
    var bytes: Int64 { files.values.reduce(0, +) }

    init(_ root: URL) throws {
        self.root = root
        var found: [String: Int64] = [:]
        var directories: [String] = []
        func visit(_ url: URL, relative: String) throws {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            switch attributes[.type] as? FileAttributeType {
            case .typeDirectory:
                directories.append(relative)
                for child in try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil) {
                    try visit(child, relative: relative.isEmpty ? child.lastPathComponent : relative + "/" + child.lastPathComponent)
                }
            case .typeRegular:
                found[relative] = (attributes[.size] as? NSNumber)?.int64Value ?? 0
            default:
                throw ModelDirectoryError("Cannot migrate a link or special file: \(url.path).")
            }
        }
        try visit(root, relative: "")
        guard directories.contains("") else { throw ModelDirectoryError("Expected a model folder at \(root.path).") }
        files = found
        folders = directories.sorted()
    }

    func copy(to destination: URL) throws {
        for folder in folders {
            try FileManager.default.createDirectory(at: destination.appending(path: folder), withIntermediateDirectories: true)
        }
        for name in files.keys.sorted() {
            try Task.checkCancellation()
            let input = try FileHandle(forReadingFrom: root.appending(path: name))
            defer { try? input.close() }
            let target = destination.appending(path: name)
            guard FileManager.default.createFile(atPath: target.path, contents: nil) else {
                throw ModelDirectoryError("Could not create \(target.path).")
            }
            let output = try FileHandle(forWritingTo: target)
            defer { try? output.close() }
            while let chunk = try input.read(upToCount: 4 * 1024 * 1024), !chunk.isEmpty {
                try Task.checkCancellation()
                try output.write(contentsOf: chunk)
            }
            try output.synchronize()
        }
    }

    /// Byte comparison is streamed, so verification never holds a weight shard in memory.
    func verify(at destination: URL) throws {
        let current = try ModelFileTree(root)
        let copied = try ModelFileTree(destination)
        guard files == current.files, folders == current.folders,
              files == copied.files, folders == copied.folders else {
            throw ModelDirectoryError("Model files changed during the move. Original files were kept at \(root.path).")
        }
        for name in files.keys.sorted() {
            let input = try FileHandle(forReadingFrom: root.appending(path: name))
            let output = try FileHandle(forReadingFrom: destination.appending(path: name))
            defer { try? input.close(); try? output.close() }
            while true {
                try Task.checkCancellation()
                let left = try input.read(upToCount: 4 * 1024 * 1024) ?? Data()
                let right = try output.read(upToCount: 4 * 1024 * 1024) ?? Data()
                guard left == right else { throw ModelDirectoryError("Verification failed for \(name). Original files were kept.") }
                if left.isEmpty { break }
            }
        }
    }
}
