// Writes index.json at the root of a model mirror: for each packed variant present, every
// file's path, size and SHA-256, and the provenance the packer stamped it with.
//
// usage: swift mirror-index.swift MIRROR_DIR [catalog-id ...]
//
// A variant is a directory named for its catalog id carrying `.zephra-packed-source`, which is
// what the app checks before it accepts a build as its own; one without the stamp is reported
// and left out, since a client that fetched it would only build the model again. The ids not
// present are listed as missing rather than failing the run, so a mirror can be filled one
// variant at a time. Paths are relative to the variant, hidden files included (the stamp is
// one), `.DS_Store` excluded, sorted, so two runs over the same files write the same bytes.
import CryptoKit
import Foundation

struct IndexedFile: Encodable {
    let path: String
    let bytes: Int64
    let sha256: String
}

struct IndexedVariant: Encodable {
    let bytes: Int64
    let source: [String]
    let files: [IndexedFile]
}

struct MirrorIndex: Encodable {
    let generated: String
    let missing: [String]
    let models: [String: IndexedVariant]
}

func digest(of url: URL) throws -> String {
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }
    var hasher = SHA256()
    // Each chunk is released inside its own pool: at the top level of an interpreted script
    // nothing drains the autorelease pool until the script ends, so without this every chunk
    // of every file stays resident and a 90 GB mirror is killed at about 45 GB read.
    while try autoreleasepool(invoking: {
        guard let chunk = try handle.read(upToCount: 8 << 20), !chunk.isEmpty else { return false }
        hasher.update(data: chunk)
        return true
    }) {}
    return hasher.finalize().map { String(format: "%02x", $0) }.joined()
}

func index(variant directory: URL) throws -> IndexedVariant {
    let stamp = directory.appending(path: ".zephra-packed-source")
    let source = try JSONDecoder().decode([String].self, from: Data(contentsOf: stamp))
    let keys: Set<URLResourceKey> = [.isRegularFileKey, .fileSizeKey]
    guard let walk = FileManager.default.enumerator(
        at: directory, includingPropertiesForKeys: Array(keys), options: [])
    else { throw CocoaError(.fileReadNoSuchFile) }
    var files: [IndexedFile] = []
    let base = directory.standardizedFileURL.path + "/"
    for case let url as URL in walk {
        let values = try url.resourceValues(forKeys: keys)
        guard values.isRegularFile == true, url.lastPathComponent != ".DS_Store" else { continue }
        let path = String(url.standardizedFileURL.path.dropFirst(base.count))
        FileHandle.standardError.write(Data("  \(path)\n".utf8))
        files.append(IndexedFile(path: path, bytes: Int64(values.fileSize ?? 0), sha256: try digest(of: url)))
    }
    files.sort { $0.path < $1.path }
    return IndexedVariant(bytes: files.reduce(0) { $0 + $1.bytes }, source: source, files: files)
}

let arguments = CommandLine.arguments.dropFirst()
guard let rootPath = arguments.first else {
    FileHandle.standardError.write(Data("usage: swift mirror-index.swift MIRROR_DIR [catalog-id ...]\n".utf8))
    exit(2)
}
let root = URL(fileURLWithPath: rootPath, isDirectory: true)
var ids = Array(arguments.dropFirst())
if ids.isEmpty {
    ids = (try? FileManager.default.contentsOfDirectory(atPath: root.path))?
        .filter { !$0.hasPrefix(".") && $0 != "index.json" }.sorted() ?? []
}

var models: [String: IndexedVariant] = [:]
var missing: [String] = []
for id in ids {
    let directory = root.appending(path: id, directoryHint: .isDirectory)
    guard FileManager.default.fileExists(atPath: directory.appending(path: ".zephra-packed-source").path) else {
        FileHandle.standardError.write(Data("mirror-index: \(id) is not built (no .zephra-packed-source); left out\n".utf8))
        missing.append(id)
        continue
    }
    FileHandle.standardError.write(Data("mirror-index: \(id)\n".utf8))
    do {
        models[id] = try index(variant: directory)
    } catch {
        FileHandle.standardError.write(Data("mirror-index: \(id): \(error)\n".utf8))
        exit(1)
    }
}

let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
let stamp = ISO8601DateFormatter().string(from: Date())
let data = try encoder.encode(MirrorIndex(generated: stamp, missing: missing, models: models))
let output = root.appending(path: "index.json")
try data.write(to: output, options: .atomic)
let total = models.values.reduce(Int64(0)) { $0 + $1.bytes }
print("mirror-index: \(models.count) variant(s), \(total / 1_000_000_000) GB, written to \(output.path)")
