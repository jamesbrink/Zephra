import Foundation

/// Identity captured when the phone saw a folder; a replacement is never that same token.
struct StorageToken {
    let itemID: String
    let url: URL
    let root: URL
    let identity: String
    init(itemID: String, url: URL, root: URL) {
        self.itemID = itemID; self.url = url; self.root = root
        identity = Self.identity(url)
    }
    static func identity(_ url: URL) -> String {
        guard let values = try? url.resourceValues(forKeys: [.fileResourceIdentifierKey, .creationDateKey]),
              let resource = values.fileResourceIdentifier, let created = values.creationDate else { return "" }
        return String(describing: resource) + String(created.timeIntervalSince1970)
    }
}
