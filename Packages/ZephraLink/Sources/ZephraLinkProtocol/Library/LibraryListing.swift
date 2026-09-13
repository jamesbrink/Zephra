import Foundation

/// A page of a revision-checked listing. The client restarts if the revision changes.
public struct LibraryListing: Codable, Hashable, Sendable {
    public let revision: String
    public let page: LibraryPage
    public init(revision: String, page: LibraryPage) {
        self.revision = revision; self.page = page
    }
}
