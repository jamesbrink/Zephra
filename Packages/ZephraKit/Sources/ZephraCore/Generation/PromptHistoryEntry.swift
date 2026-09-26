import Foundation

/// One admitted prompt, independent of whether its images finished successfully.
public struct PromptHistoryEntry: Codable, Hashable, Sendable, Identifiable {
    public let id: UUID
    public let prompt: String
    public let createdAt: Date
    public init(id: UUID = UUID(), prompt: String, createdAt: Date = Date()) {
        self.id = id; self.prompt = prompt; self.createdAt = Date(timeIntervalSince1970: (createdAt.timeIntervalSince1970 * 1000).rounded() / 1000)
    }
    private enum CodingKeys: String, CodingKey { case id, prompt, createdAt }
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        prompt = try values.decode(String.self, forKey: .prompt)
        createdAt = Date(timeIntervalSince1970: Double(try values.decode(Int64.self, forKey: .createdAt)) / 1000)
    }
    public func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(id, forKey: .id)
        try values.encode(prompt, forKey: .prompt)
        try values.encode(Int64((createdAt.timeIntervalSince1970 * 1000).rounded()), forKey: .createdAt)
    }
}
