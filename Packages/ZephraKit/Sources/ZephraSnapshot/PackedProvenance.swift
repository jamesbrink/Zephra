import Foundation
import ZephraCore

/// Records the source a packed model was requested from, before its atomic publication.
public enum PackedProvenance {
    /// The words that identify a build: what the stamp holds, and what a mirror's index repeats
    /// so a variant can be matched against the catalog before a byte of it is fetched.
    static func identity(_ model: ModelDescriptor) -> [String] {
        var parts = [model.id, model.sourceName, String(describing: model.quantization)]
        if case .huggingFace(_, let revision, let patterns) = model.source {
            parts += [revision] + patterns.sorted()
        }
        return parts
    }

    public static func write(_ model: ModelDescriptor, into directory: URL) throws {
        try JSONEncoder().encode(identity(model)).write(
            to: directory.appending(path: ".zephra-packed-source"), options: .atomic)
    }

    static func matches(_ model: ModelDescriptor, in directory: URL) -> Bool {
        let record = directory.appending(path: ".zephra-packed-source")
        if let data = try? Data(contentsOf: record) {
            return (try? JSONDecoder().decode([String].self, from: data)) == identity(model)
        }
        // Preserve manually packed and older main builds; explicit revisions require proof.
        if case .huggingFace(_, let revision, _) = model.source, revision != "main" { return false }
        return true
    }
}
