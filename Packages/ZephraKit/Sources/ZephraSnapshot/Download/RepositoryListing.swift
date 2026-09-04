import Foundation

/// What a repository holds, read from the hub's tree endpoint.
///
/// Only the reading is here, and it is pure: bytes and a response in, files and the next page
/// out. The requests themselves are `ModelDownloader+Listing.swift`, so what the hub's JSON
/// actually says can be pinned by a test with no network anywhere near it.
///
/// The endpoint answers with an array of entries, each a `type` of `file` or `directory`, a
/// `path`, a `size`, and for a file kept in Git LFS — which every weights file is — an `lfs`
/// object carrying the real size. `?recursive=true` flattens the directories, and a repository
/// with more entries than one page holds says where the rest are in a `Link` header.
public nonisolated enum RepositoryListing {
    /// The files one page of the tree endpoint names, directories dropped.
    ///
    /// A file's size is the `lfs` size when there is one: for an LFS file the plain `size` is
    /// the pointer's, a couple of hundred bytes, and weighting progress by that would show a
    /// thirteen-gigabyte download finishing in the first second.
    public static func files(in data: Data) throws -> [RepositoryFile] {
        guard let entries = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw ModelDownloadError.unreadableListing
        }
        return entries.compactMap { entry in
            guard entry["type"] as? String == "file", let path = entry["path"] as? String
            else { return nil }
            let lfs = (entry["lfs"] as? [String: Any])?["size"] as? NSNumber
            let plain = entry["size"] as? NSNumber
            return RepositoryFile(path: path, bytes: (lfs ?? plain)?.int64Value ?? 0)
        }
    }

    /// The next page of a listing, or nil when this was the last.
    ///
    /// The header is RFC 8288: `<https://…>; rel="next"`, possibly beside other relations. The
    /// URL is taken as the hub gave it, cursor and all; building the next page ourselves would
    /// mean guessing at a cursor format that is the hub's to change.
    public static func nextPage(after response: HTTPURLResponse) -> URL? {
        guard let header = response.value(forHTTPHeaderField: "Link") else { return nil }
        for link in header.split(separator: ",") {
            let parts = link.split(separator: ";")
            guard parts.count >= 2,
                  parts.dropFirst().contains(where: { $0.contains("rel=\"next\"") })
            else { continue }
            let target = parts[0].trimmingCharacters(in: .whitespaces)
            guard target.hasPrefix("<"), target.hasSuffix(">") else { continue }
            return URL(string: String(target.dropFirst().dropLast()))
        }
        return nil
    }
}
