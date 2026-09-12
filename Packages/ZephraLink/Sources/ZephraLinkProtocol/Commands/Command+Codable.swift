import Foundation

/// The JSON one command is: a tagged object, for the reason `StateDelta`'s is.
extension Command: Codable {
    private enum CodingKeys: String, CodingKey {
        case kind, request, id, modelID, names, on, tags, name, factor, pixels, offset, limit
        case fromChunk
    }

    /// The tag, which is also the case name.
    public enum Kind: String, Codable, Hashable, Sendable, CaseIterable {
        case resync, enqueue, cancel, removeFromQueue, clearQueue, switchModel, setFavourite
        case setTags, delete, upscale, animate, fetchThumbnail, fetchFile, libraryPage
    }

    /// Which command this is, without decoding its payload.
    public var kind: Kind {
        switch self {
        case .resync: .resync
        case .enqueue: .enqueue
        case .cancel: .cancel
        case .removeFromQueue: .removeFromQueue
        case .clearQueue: .clearQueue
        case .switchModel: .switchModel
        case .setFavourite: .setFavourite
        case .setTags: .setTags
        case .delete: .delete
        case .upscale: .upscale
        case .animate: .animate
        case .fetchThumbnail: .fetchThumbnail
        case .fetchFile: .fetchFile
        case .libraryPage: .libraryPage
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .kind)
        switch self {
        case .enqueue(let request): try container.encode(request, forKey: .request)
        case .resync, .cancel, .clearQueue: break
        case .removeFromQueue(let id): try container.encode(id, forKey: .id)
        case .switchModel(let id): try container.encode(id, forKey: .modelID)
        case .setFavourite(let names, let on):
            try container.encode(names, forKey: .names)
            try container.encode(on, forKey: .on)
        case .setTags(let names, let tags):
            try container.encode(names, forKey: .names)
            try container.encode(tags, forKey: .tags)
        case .delete(let names): try container.encode(names, forKey: .names)
        case .upscale(let name, let factor):
            try container.encode(name, forKey: .name)
            try container.encode(factor, forKey: .factor)
        case .animate(let name): try container.encode(name, forKey: .name)
        case .fetchThumbnail(let name, let pixels):
            try container.encode(name, forKey: .name)
            try container.encode(pixels, forKey: .pixels)
        case .fetchFile(let name, let fromChunk):
            try container.encode(name, forKey: .name)
            // Written only when it is asking for a tail, so the golden string every build has
            // ever sent for a whole file is unchanged.
            if fromChunk > 0 { try container.encode(fromChunk, forKey: .fromChunk) }
        case .libraryPage(let offset, let limit):
            try container.encode(offset, forKey: .offset)
            try container.encode(limit, forKey: .limit)
        }
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        func value<T: Decodable>(_ type: T.Type, _ key: CodingKeys) throws -> T {
            try container.decode(type, forKey: key)
        }
        switch try container.decode(Kind.self, forKey: .kind) {
        case .resync: self = .resync
        case .enqueue: self = .enqueue(try value(GenerationRequest.self, .request))
        case .cancel: self = .cancel
        case .removeFromQueue: self = .removeFromQueue(try value(UUID.self, .id))
        case .clearQueue: self = .clearQueue
        case .switchModel: self = .switchModel(try value(String.self, .modelID))
        case .setFavourite:
            self = .setFavourite(
                names: try value([String].self, .names), on: try value(Bool.self, .on))
        case .setTags:
            self = .setTags(
                names: try value([String].self, .names), tags: try value([String].self, .tags))
        case .delete: self = .delete(try value([String].self, .names))
        case .upscale:
            self = .upscale(name: try value(String.self, .name), factor: try value(Int.self, .factor))
        case .animate: self = .animate(name: try value(String.self, .name))
        case .fetchThumbnail:
            self = .fetchThumbnail(
                name: try value(String.self, .name), pixels: try value(Int.self, .pixels))
        case .fetchFile:
            self = .fetchFile(
                name: try value(String.self, .name),
                fromChunk: try container.decodeIfPresent(UInt32.self, forKey: .fromChunk) ?? 0)
        case .libraryPage:
            self = .libraryPage(
                offset: try value(Int.self, .offset), limit: try value(Int.self, .limit))
        }
    }
}
