import ZephraCore

/// Where one part of a download is read from, which decides how it is listed and how each of
/// its files is addressed.
public enum DownloadOrigin: Hashable, Sendable {
    /// A Hugging Face repository: pinned to a commit, listed through the tree endpoint, each
    /// file at `/<repo>/resolve/<commit>/<path>`.
    case huggingFace
    /// A mirror of packed variants: listed by its `index.json`, each file at
    /// `<base>/<id>/<path>`, and accepted only when the index says the variant was packed from
    /// exactly `identity` — the same words `PackedProvenance` stamps into the variant — so a
    /// mirror built against an older catalog is "not there" rather than loaded.
    case mirror(ModelMirror, identity: [String])
}
