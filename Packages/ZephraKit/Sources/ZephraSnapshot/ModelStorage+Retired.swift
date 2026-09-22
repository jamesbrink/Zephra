import Foundation
import ZephraCore

extension ModelStorage {
    /// Directories under the models roots that no catalog entry claims.
    ///
    /// `claimed` is the set of directory paths the catalog walk already produced, so a
    /// release two variants pack from is never listed twice. Only what Zephra itself writes
    /// is listed: a variant is a directory carrying one of the three files a packed or
    /// downloaded snapshot always has, and a download is a directory under `Downloads`
    /// spelled `<org>--<repo>`. Anything else under the root is the person's own folder and
    /// is left alone, which is the whole reason this is a rule about markers rather than a
    /// listing.
    static func retired(claimed: Set<String>, locations: ModelLocations) -> [ModelStorageItem] {
        var items: [ModelStorageItem] = []
        for root in locations.roots {
            for child in directoryChildren(of: root) {
                if child.lastPathComponent == "Downloads" {
                    for download in directoryChildren(of: child) {
                        appendDownload(download, claimed: claimed, locations: locations, to: &items)
                    }
                    continue
                }
                appendVariant(child, claimed: claimed, locations: locations, to: &items)
            }
        }
        return items
    }

    private static let variantMarkers = [".zephra-packed-source", "quantization.json", "model_index.json"]

    private static func appendDownload(
        _ url: URL, claimed: Set<String>, locations: ModelLocations, to items: inout [ModelStorageItem]
    ) {
        let name = url.lastPathComponent
        guard !isPartial(url), name.contains("--"), !claimed.contains(standardizedPath(url)) else {
            return
        }
        items.append(
            ModelStorageItem(
                name: name.replacingOccurrences(of: "--", with: "/"), kind: .download, url: url,
                location: place(url, in: locations), modelIDs: [],
                isComplete: HubSnapshotCheck.isComplete(url), origin: .retired))
    }

    private static func appendVariant(
        _ url: URL, claimed: Set<String>, locations: ModelLocations, to items: inout [ModelStorageItem]
    ) {
        guard !isPartial(url), hasVariantMarker(url), !claimed.contains(standardizedPath(url)) else {
            return
        }
        items.append(
            ModelStorageItem(
                name: url.lastPathComponent, kind: .built, url: url,
                location: place(url, in: locations), modelIDs: [], isComplete: true, origin: .retired))
    }

    private static func hasVariantMarker(_ directory: URL) -> Bool {
        let files = FileManager.default
        return variantMarkers.contains {
            files.fileExists(atPath: directory.appending(path: $0).path(percentEncoded: false))
        }
    }

    private static func isPartial(_ url: URL) -> Bool {
        url.lastPathComponent.hasSuffix(".partial")
    }

    /// A directory's path with the trailing slash off, so an entry from `contentsOfDirectory`
    /// (which carries one) compares equal to one built with `appending(path:)` (which does not).
    private static func standardizedPath(_ url: URL) -> String {
        let path = url.standardizedFileURL.path(percentEncoded: false)
        return path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
    }

    /// Every real directory immediately under `url`, symbolic links excluded, or none where
    /// `url` does not exist. The same `.isSymbolicLinkKey` check `ModelStorage.measure` uses, so
    /// a Delete offered here never follows a link out of the root.
    private static func directoryChildren(of url: URL) -> [URL] {
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey]
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: url, includingPropertiesForKeys: Array(keys))
        else { return [] }
        return entries.filter { entry in
            guard let values = try? entry.resourceValues(forKeys: keys) else { return false }
            return values.isDirectory == true && values.isSymbolicLink != true
        }
    }

    /// Where a retired directory is, the same rule a claimed row's `location` follows: the path
    /// under the current root, or the whole path when it is under a previous one.
    private static func place(_ url: URL, in locations: ModelLocations) -> String {
        let root = standardizedPath(locations.root) + "/"
        let path = standardizedPath(url)
        guard path.hasPrefix(root) else { return path }
        return String(path.dropFirst(root.count))
    }
}
