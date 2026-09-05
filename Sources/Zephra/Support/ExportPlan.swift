import Foundation

/// What an export of some files into a folder would do, worked out before anything is
/// written: which copies are free to go, which would land on another file, and which would
/// land on themselves.
///
/// Pure, so the questions the export asks — is the destination taken, is it the very same
/// file — come in as closures and the arithmetic is pinned by a test without a disk.
nonisolated struct ExportPlan: Equatable, Sendable {
    /// One file and where it is going.
    struct Copy: Equatable, Sendable {
        let source: URL
        let destination: URL
    }

    /// Copies whose destination is free.
    let copies: [Copy]
    /// Copies whose destination is another file, or another copy of this plan: writing them
    /// would overwrite something, so they wait on a choice.
    let collisions: [Copy]
    /// Sources whose destination is the source itself. There is nothing to do for them, and
    /// doing anything at all — removing the destination, say — would destroy the source.
    let alreadyThere: [URL]

    /// The plan for putting `files` into `folder` under their own names.
    static func make(
        files: [URL], into folder: URL,
        exists: (URL) -> Bool, isSameFile: (URL, URL) -> Bool
    ) -> ExportPlan {
        make(
            copies: files.map { Copy(source: $0, destination: folder.appending(path: $0.lastPathComponent)) },
            exists: exists, isSameFile: isSameFile)
    }

    /// The plan for a list of copies whose destinations are already decided.
    static func make(
        copies requested: [Copy], exists: (URL) -> Bool, isSameFile: (URL, URL) -> Bool
    ) -> ExportPlan {
        var copies: [Copy] = []
        var collisions: [Copy] = []
        var alreadyThere: [URL] = []
        var planned: Set<String> = []
        for copy in requested {
            let name = copy.destination.lastPathComponent
            if exists(copy.destination), isSameFile(copy.source, copy.destination) {
                alreadyThere.append(copy.source)
            } else if exists(copy.destination) || planned.contains(name) {
                collisions.append(copy)
            } else {
                copies.append(copy)
                planned.insert(name)
            }
        }
        return ExportPlan(copies: copies, collisions: collisions, alreadyThere: alreadyThere)
    }

    /// "name 2.png", "name 3.png", and so on: the first that is neither in `taken` nor on the
    /// disk, which is the name the Finder's own Keep Both gives.
    static func keepBothName(for destination: URL, taken: Set<String>, exists: (URL) -> Bool) -> URL {
        let folder = destination.deletingLastPathComponent()
        let stem = destination.deletingPathExtension().lastPathComponent
        let ext = destination.pathExtension
        var counter = 2
        while true {
            var candidate = folder.appending(path: "\(stem) \(counter)")
            if !ext.isEmpty { candidate = candidate.appendingPathExtension(ext) }
            if !taken.contains(candidate.lastPathComponent), !exists(candidate) { return candidate }
            counter += 1
        }
    }

    /// The same plan with every collision renamed out of the way, so nothing is overwritten.
    func keepingBoth(exists: (URL) -> Bool) -> ExportPlan {
        var taken = Set(copies.map(\.destination.lastPathComponent))
        var renamed = copies
        for collision in collisions {
            let destination = Self.keepBothName(for: collision.destination, taken: taken, exists: exists)
            taken.insert(destination.lastPathComponent)
            renamed.append(Copy(source: collision.source, destination: destination))
        }
        return ExportPlan(copies: renamed, collisions: [], alreadyThere: alreadyThere)
    }

    /// The same plan with every collision promoted to a copy: the existing files are replaced.
    func replacing() -> ExportPlan {
        ExportPlan(copies: copies + collisions, collisions: [], alreadyThere: alreadyThere)
    }
}
