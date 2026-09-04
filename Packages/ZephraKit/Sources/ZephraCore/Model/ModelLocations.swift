import Foundation

/// The folder Zephra keeps model weights in, and what goes where inside it.
///
/// One root, chosen in Settings and defaulting to Application Support, with two kinds of thing
/// under it: what was fetched from a repository, a directory per repository under `Downloads`
/// holding the files exactly as the repository names them, and what was packed here, a
/// directory per model beside it. Nothing outside the root is ever written, which is what makes
/// an external disk a valid answer for a Mac whose boot volume cannot hold sixty gigabytes.
///
/// It is a value passed down the layers rather than a preference read wherever it is wanted:
/// the engine holds one and hands it to every backend call, and the composition root is the
/// only place that knows a preference decided it. Tests hand in a scratch folder the same way.
public struct ModelLocations: Hashable, Sendable {
    /// The folder everything Zephra downloads or builds is kept under.
    public let root: URL
    /// Roots the folder was set to before, newest first. Nothing is written under them any
    /// more, but what was downloaded or built there is still found: changing the folder moves
    /// nothing, and a model a person already has must never be fetched again because a
    /// setting moved.
    public let previous: [URL]

    /// Keeps models under `root`, still looking under `previous` for what is already there.
    public init(root: URL, previous: [URL] = []) {
        self.root = root
        self.previous = previous.filter { Self.folder($0) != Self.folder(root) }
    }

    /// Every root, the current one first.
    public var roots: [URL] { [root] + previous }

    /// Where models are kept until the user says otherwise.
    public static let `default` = ModelLocations(
        root: URL.applicationSupportDirectory
            .appending(path: "Zephra/Models", directoryHint: .isDirectory)
    )

    /// The folder every download lands in, for a settings row to name and open.
    public var downloadsRoot: URL {
        root.appending(path: "Downloads", directoryHint: .isDirectory)
    }

    /// Where `repoID` is downloaded to: `Downloads/<org>--<repo>`, flat, the files named as the
    /// repository names them.
    ///
    /// The two parts are joined with dashes rather than nested so that one listing of
    /// `Downloads` is one row per download, and so a directory seen in the Finder says which
    /// repository it came from without being opened.
    public func downloads(repoID: String) -> URL {
        downloadsRoot.appending(
            path: repoID.replacingOccurrences(of: "/", with: "--"), directoryHint: .isDirectory)
    }

    /// Where an adapter's repository is downloaded to. An adapter is a download like any other,
    /// so it lands in `Downloads` beside the releases rather than in a folder of its own: one
    /// listing of that directory is still one row per repository, and a Delete in Settings is
    /// still a repository.
    public func adapter(_ adapter: ModelAdapter) -> URL {
        downloads(repoID: adapter.repoID)
    }

    /// The adapter file itself, under this root.
    public func adapterFile(_ adapter: ModelAdapter) -> URL {
        self.adapter(adapter).appending(path: adapter.file)
    }

    /// Where `repoID`'s download would be under each root, the current one first.
    public func downloadsCandidates(repoID: String) -> [URL] {
        roots.map { ModelLocations(root: $0).downloads(repoID: repoID) }
    }

    /// The adapter file wherever it is, under this root or one the folder used to be, or nil
    /// when it is nowhere: what a build is handed, and what says an adapter is not missing.
    public func adapterFileOnDisk(_ adapter: ModelAdapter) -> URL? {
        roots.map { ModelLocations(root: $0).adapterFile(adapter) }
            .first { FileManager.default.fileExists(atPath: $0.path(percentEncoded: false)) }
    }

    /// The descriptor's adapters whose file is not here yet, and so still have to be fetched.
    public func missingAdapters(of descriptor: ModelDescriptor) -> [ModelAdapter] {
        descriptor.adapters.filter { adapterFileOnDisk($0) == nil }
    }

    /// What choosing `descriptor` would still transfer: the release unless it is already here,
    /// and every adapter that is not. This is what a picker states, so a release found in the
    /// cache with its distillation missing reads as the distillation's cost, not the release's.
    public func bytesToFetch(for descriptor: ModelDescriptor, releasePresent: Bool) -> Int64 {
        (releasePresent ? 0 : descriptor.downloadBytes)
            + missingAdapters(of: descriptor).reduce(0) { $0 + $1.bytes }
    }

    /// Where a variant packed on this Mac lives: `<root>/<descriptor id>`, the naming every
    /// locally built variant has followed since `make quantize` wrote the first one.
    public func built(_ descriptor: ModelDescriptor) -> URL {
        root.appending(path: descriptor.id, directoryHint: .isDirectory)
    }

    /// Every directory a built variant of `descriptor` could be in, best answer first.
    ///
    /// A descriptor whose source is a directory names it absolutely, and that is the only
    /// place it is. No catalog entry does any more, but a descriptor is not only the catalog —
    /// `ZephraBench` points one at a folder to measure, and a variant built by hand elsewhere
    /// is still loadable — and the folder named is the one meant: `ZephraBench --snapshot
    /// /external/foo` with nothing at that path must fail, not quietly measure a `foo` that
    /// happens to sit under the app's own root.
    public func builtCandidates(for descriptor: ModelDescriptor) -> [URL] {
        guard case .localDirectory(let named) = descriptor.source else {
            return roots.map { $0.appending(path: descriptor.id, directoryHint: .isDirectory) }
        }
        return [named]
    }

    /// A directory's path with the trailing slash off, so two URLs naming one folder compare
    /// equal whether or not whoever built them said it was a directory.
    private static func folder(_ url: URL) -> String {
        let path = url.standardizedFileURL.path(percentEncoded: false)
        return path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
    }
}
