import Foundation

/// The file-system half of a scan: listing a folder, and turning one PNG into an item.
extension LibraryScan {
    /// The PNGs in one folder, with the two facts a rescan compares. A folder that is not there
    /// lists as empty, because a library with nothing imported into it is a normal state.
    ///
    /// Files iCloud has evicted are left out: their metadata is there but their bytes are not,
    /// and asking for them would start a download nobody asked for.
    func listings(in directory: URL) -> [Listing] {
        let keys: [URLResourceKey] = [
            .contentModificationDateKey, .fileSizeKey, .ubiquitousItemDownloadingStatusKey,
        ]
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants, .skipsPackageDescendants]
        )) ?? []
        return contents.compactMap { url in
            guard url.pathExtension.lowercased() == "png" else { return nil }
            guard let values = try? url.resourceValues(forKeys: Set(keys)) else { return nil }
            if let status = values.ubiquitousItemDownloadingStatus, status != .current {
                return nil
            }
            return Listing(
                url: url.standardizedFileURL,
                modifiedAt: values.contentModificationDate ?? .distantPast,
                size: Int64(values.fileSize ?? 0)
            )
        }
    }

    /// One file read into an item, or nil when Zephra has no business showing it.
    ///
    /// One header read answers everything: the record, the annotation, and, in the sources
    /// folder, where the picture came from. A file in the generated folders needs a generation
    /// record and a file in the sources folder needs an import record; without one, the file is
    /// somebody else's and the library leaves it alone.
    func item(_ listing: Listing, in collection: LibraryCollection) -> LibraryItem? {
        guard let text = try? PNGTextChunks.read(fromHeaderOf: listing.url) else { return nil }
        let provenance: LibraryProvenance
        switch collection {
        case .generated, .recentlyDeleted:
            guard let record = GenerationRecord.decode(from: text) else { return nil }
            provenance = .generated(record)
        case .sources:
            guard let source = SourceRecord.decode(from: text) else { return nil }
            provenance = .imported(source)
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
