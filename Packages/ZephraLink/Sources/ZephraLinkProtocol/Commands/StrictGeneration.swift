import Foundation

/// A request whose exact settings and installed-only execution policy must be preserved.
public struct StrictGeneration: Codable, Hashable, Sendable {
    public var request: GenerationRequest
    public let input: GenerationInput?
    public init(request: GenerationRequest, input: GenerationInput? = nil) {
        self.request = request
        self.input = input
    }
    public func digest() throws -> String {
        let canonical = StrictGeneration(request: GenerationRequest(
            modelID: request.modelID, count: request.count, settings: request.settings,
            requestID: request.requestID), input: input)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return GenerationInput.digest(try encoder.encode(canonical))
    }
}
