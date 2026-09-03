import Foundation

/// The folders the library is made of. Three directories, one per collection, and nothing else
/// knows their names.
extension ImageLibrary {
    /// Where deleted images wait out their thirty days, Photos-style: in the library, not in
    /// the Finder's Trash, so restoring one is a click rather than an excursion.
    public static let recentlyDeletedFolderName = "Recently Deleted"
    /// Where imported pictures live, apart from the images generated from them.
    public static let sourcesFolderName = "Sources"

    /// The directory one collection is kept in. Existence is not implied: `Sources` is only
    /// created when something is imported into it.
    public func directory(for collection: LibraryCollection) -> URL {
        switch collection {
        case .generated: root
        case .recentlyDeleted:
            root.appending(path: Self.recentlyDeletedFolderName, directoryHint: .isDirectory)
        case .sources:
            root.appending(path: Self.sourcesFolderName, directoryHint: .isDirectory)
        }
    }

    /// Every folder a scan walks, with the collection each one stands for.
    ///
    /// The order is the one the sidebar reads in, and it is also the order a scan produces
    /// items in, which is why the generated root comes first.
    public var scanRoots: [(collection: LibraryCollection, url: URL)] {
        LibraryCollection.allCases.map { ($0, directory(for: $0)) }
    }
}
