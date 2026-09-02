import Foundation

/// How a quantization rule recognises the tensors it applies to.
///
/// Deliberately three cases and no regular expressions. Every rule any published export needs
/// is a fixed affix or an infix — `all_final_layer` at the front, `img_mod` anywhere — and an
/// exhaustive enum can be read in a log line and pinned by a test, which a pattern language
/// cannot.
public enum NamePattern: Hashable, Sendable {
    /// Matches a tensor whose name starts with this.
    case prefix(String)
    /// Matches a tensor whose name ends with this.
    case suffix(String)
    /// Matches a tensor whose name contains this anywhere, which is how a rule reaches the same
    /// submodule in every one of a transformer's blocks.
    case contains(String)

    /// Whether `name` matches. The name is the full tensor key, `.weight` suffix and all.
    public func matches(_ name: String) -> Bool {
        switch self {
        case .prefix(let text): name.hasPrefix(text)
        case .suffix(let text): name.hasSuffix(text)
        case .contains(let text): name.contains(text)
        }
    }
}
