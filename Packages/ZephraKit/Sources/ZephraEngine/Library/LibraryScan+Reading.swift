import Foundation

/// The file-system half of a scan: listing a folder, and turning one PNG into an item.
extension LibraryScan {
    /// The PNGs in one folder, with the two facts a rescan compares. A folder that is not there
    /// lists as empty, because a library with nothing imported into it is a normal state.
    ///
    /// Files iCloud has evicted are left out: their metadata is there but their bytes are not,
    /// and asking for them would start a download nobody asked for.
    func listings(in directory: URL) -> [Listing] {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: Array(Self.listingKeys),
            options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants, .skipsPackageDescendants]
        )) ?? []
        return contents.compactMap(listing(of:))
    }

    /// One file's listing, for the case where the caller already knows which file changed and a
    /// whole directory listing would be the expensive way to find out.
    func listing(of url: URL) -> Listing? {
        guard url.pathExtension.lowercased() == "png",
              let values = try? url.resourceValues(forKeys: Self.listingKeys)
        else { return nil }
        if let status = values.ubiquitousItemDownloadingStatus, status != .current { return nil }
        return Listing(
            url: url.standardizedFileURL,
            modifiedAt: values.contentModificationDate ?? .distantPast,
            size: Int64(values.fileSize ?? 0)
        )
    }

    static let listingKeys: Set<URLResourceKey> = [
        .contentModificationDateKey, .fileSizeKey, .ubiquitousItemDownloadingStatusKey,
    ]

    /// One file read into an item, or nil when Zephra has no business showing it.
    ///
    /// One header read answers everything: the record, the annotation, and, in the sources
    /// folder, where the picture came from. A file in the generated folder needs a generation
    /// record, a file in the sources folder needs an import record, and Recently Deleted holds
    /// either, since both kinds are deleted into it; without one, the file is somebody else's
    /// and the library leaves it alone.
    func item(_ listing: Listing, in collection: LibraryCollection) -> LibraryItem? {
        guard let text = try? PNGTextChunks.read(fromHeaderOf: listing.url) else { return nil }
        let provenance: LibraryProvenance
        switch collection {
        case .generated:
            guard let record = GenerationRecord.decode(from: text) else { return nil }
            provenance = .generated(record)
        case .sources:
            guard let source = SourceRecord.decode(from: text) else { return nil }
            provenance = .imported(source)
        case .recentlyDeleted:
            if let record = GenerationRecord.decode(from: text) {
                provenance = .generated(record)
            } else if let source = SourceRecord.decode(from: text) {
                provenance = .imported(source)
            } else {
                return nil
            }
        }
        return LibraryItem(
            url: listing.url,
            collection: collection,
            provenance: provenance,
            annotation: LibraryAnnotation.decode(from: text),
            fileSize: listing.size,
            contentModifiedAt: listing.modifiedAt,
            calendar: calendar
        )
    }
}
