import Foundation

/// The JSON one library change is, written by hand.
///
/// `{"kind":"reset","entries":[...],"total":12}` rather than Swift's own enum encoding, which
/// nests the payload under the case name and makes the shape depend on how many associated
/// values a case happens to have. A tagged object reads the same for every case, and a log line
/// or a capture says what happened without decoding it.
extension LibraryChange {
    private enum CodingKeys: String, CodingKey { case kind, entries, names, total }
    private enum Kind: String, Codable { case reset, upserted, removed }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .reset(let entries, let total):
            try container.encode(Kind.reset, forKey: .kind)
            try container.encode(entries, forKey: .entries)
            try container.encode(total, forKey: .total)
        case .upserted(let entries):
            try container.encode(Kind.upserted, forKey: .kind)
            try container.encode(entries, forKey: .entries)
        case .removed(let names):
            try container.encode(Kind.removed, forKey: .kind)
            try container.encode(names, forKey: .names)
        }
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .reset:
            self = .reset(
                try container.decode([LibraryEntry].self, forKey: .entries),
                total: try container.decode(Int.self, forKey: .total))
        case .upserted:
            self = .upserted(try container.decode([LibraryEntry].self, forKey: .entries))
        case .removed:
            self = .removed(try container.decode([String].self, forKey: .names))
        }
    }
}
