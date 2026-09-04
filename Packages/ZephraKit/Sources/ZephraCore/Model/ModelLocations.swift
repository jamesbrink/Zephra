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

    /// Keeps models under `root`.
    public init(root: URL) {
        self.root = root
    }

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

    /// Where a variant packed on this Mac lives: `<root>/<descriptor id>`, the naming every
    /// locally built variant has followed since `make quantize` wrote the first one.
    public func built(_ descriptor: ModelDescriptor) -> URL {
        root.appending(path: descriptor.id, directoryHint: .isDirectory)
    }

    /// Every directory a built variant of `descriptor` could be in, best answer first.
    ///
    /// A catalog entry whose source is a directory names it absolutely, under the default root.
    /// Once the root has been moved that entry still points at the old folder, and a model
    /// built before the move is still perfectly usable there — so both are offered: this root
    /// first, because a folder the user chose is the one they meant, and the folder the catalog
    /// names after it, so nothing already built stops working when the setting changes.
    public func builtCandidates(for descriptor: ModelDescriptor) -> [URL] {
        let mine = built(descriptor)
        guard case .localDirectory(let named) = descriptor.source else { return [mine] }
        let relocated = root.appending(
            path: named.lastPathComponent, directoryHint: .isDirectory)
        guard Self.folder(relocated) != Self.folder(named) else { return [relocated] }
        return [relocated, named]
    }

    /// A directory's path with the trailing slash off, so two URLs naming one folder compare
    /// equal whether or not whoever built them said it was a directory.
    private static func folder(_ url: URL) -> String {
        let path = url.standardizedFileURL.path(percentEncoded: false)
        return path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
    }
}
