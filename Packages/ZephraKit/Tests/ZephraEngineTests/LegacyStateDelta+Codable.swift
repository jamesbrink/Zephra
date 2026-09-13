// Frozen outer wire decoder from pre-multi-host 95ede16. Nested DTOs are shared.
import Foundation
import ZephraLinkProtocol

/// The JSON one delta is, written by hand for the reason `LibraryChange`'s is: a tagged object
/// whose shape does not change with the number of associated values, so the wire reads as
/// English and a golden-string test can pin it.
extension LegacyStateDelta: Codable {
    private enum CodingKeys: String, CodingKey { case kind, value }

    /// The tag, which is also the case name.
    enum Kind: String, Codable, Hashable, Sendable, CaseIterable {
        case engine, queue, running, historyInserted, historyRemoved, model
        case availability, downloads, today, library, acceptsWork
    }

    /// Which change this is, without decoding its value.
    var kind: Kind {
        switch self {
        case .engine: .engine
        case .queue: .queue
        case .running: .running
        case .historyInserted: .historyInserted
        case .historyRemoved: .historyRemoved
        case .model: .model
        case .availability: .availability
        case .downloads: .downloads
        case .today: .today
        case .library: .library
        case .acceptsWork: .acceptsWork
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .kind)
        switch self {
        case .engine(let value): try container.encode(value, forKey: .value)
        case .queue(let value): try container.encode(value, forKey: .value)
        case .running(let value): try container.encode(value, forKey: .value)
        case .historyInserted(let value): try container.encode(value, forKey: .value)
        case .historyRemoved(let value): try container.encode(value, forKey: .value)
        case .model(let value): try container.encode(value, forKey: .value)
        case .availability(let value): try container.encode(value, forKey: .value)
        case .downloads(let value): try container.encode(value, forKey: .value)
        case .today(let value): try container.encode(value, forKey: .value)
        case .library(let value): try container.encode(value, forKey: .value)
        case .acceptsWork(let value): try container.encode(value, forKey: .value)
        }
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        func value<T: Decodable>(_ type: T.Type) throws -> T {
            try container.decode(type, forKey: .value)
        }
        switch try container.decode(Kind.self, forKey: .kind) {
        case .engine: self = .engine(try value(EngineStateDTO.self))
        case .queue: self = .queue(try value([QueuedEntry].self))
        case .running: self = .running(try container.decodeIfPresent(QueuedEntry.self, forKey: .value))
        case .historyInserted: self = .historyInserted(try value(HistoryEntry.self))
        case .historyRemoved: self = .historyRemoved(try value(UUID.self))
        case .model: self = .model(try value(ModelSummary.self))
        case .availability: self = .availability(try value([String: AvailabilityDTO].self))
        case .downloads: self = .downloads(try value([DownloadDTO].self))
        case .today: self = .today(try value([RunSummary].self))
        case .library: self = .library(try value(LibraryChange.self))
        case .acceptsWork: self = .acceptsWork(try value(Bool.self))
        }
    }
}
