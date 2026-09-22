import Foundation

/// A request whose exact settings and installed-only execution policy must be preserved.
public struct StrictGeneration: Hashable, Sendable {
    public var request: GenerationRequest
    /// What each reference picture is, without its pixels: a size, a length and a digest the
    /// Mac checks the blob against, in the order the model reads them.
    public let inputs: [GenerationInput]

    /// The first of those, which is what a Mac reading one picture checks.
    public var input: GenerationInput? { inputs.first }

    public init(request: GenerationRequest, input: GenerationInput? = nil) {
        self.init(request: request, inputs: input.map { [$0] } ?? [])
    }

    public init(request: GenerationRequest, inputs: [GenerationInput]) {
        self.request = request
        self.inputs = inputs
    }

    /// What names this work, whatever blob ids this attempt happens to use.
    ///
    /// The request is rebuilt without them, so a retry that sends its pictures again under
    /// fresh ids digests the same. A one-picture generation encodes exactly the bytes it
    /// encoded before several were possible, so every receipt already written still matches
    /// the work it names.
    public func digest() throws -> String {
        let canonical = StrictGeneration(request: GenerationRequest(
            modelID: request.modelID, count: request.count, settings: request.settings,
            requestID: request.requestID), inputs: inputs)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return GenerationInput.digest(try encoder.encode(canonical))
    }
}
