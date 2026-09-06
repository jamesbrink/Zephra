import Foundation

extension ModelCatalog {
    /// Where the variants the catalog packs are published ready-made: `make mirror`'s output,
    /// synced to the `models/` prefix of the `zephra-assets-urandom-io` bucket and served by
    /// CloudFront. Every variant built locally names it, so a Mac fetches 6.7 GB of Z-Image
    /// Turbo instead of its 32.9 GB release, and never spends the minute packing it.
    ///
    /// One mirror for the whole catalog rather than one per entry: the host is a deployment
    /// fact, not a property of a model, and the index it serves is what says which variants
    /// are actually there.
    static let mirror = ModelMirror(base: URL(string: "https://zephra-assets.urandom.io/models")!)
}
