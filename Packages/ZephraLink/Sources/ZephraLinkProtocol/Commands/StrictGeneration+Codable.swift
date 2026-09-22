import Foundation

/// Reading and writing a strict generation.
///
/// Hand-written for one reason, and it is the same reason `GenerationRequest+Codable` is: the
/// single `input` is written always and the list only past one picture, so a one-picture
/// generation is byte for byte what it was before several were possible. `digest()` is the
/// encoded form, and the multi-host receipt ledger is a table of digests already written, so a
/// key that moved would be every accepted submit named twice.
extension StrictGeneration: Codable {
    private enum CodingKeys: String, CodingKey {
        case request, input, inputs
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(request, forKey: .request)
        try container.encodeIfPresent(input, forKey: .input)
        if inputs.count > 1 {
            try container.encode(inputs, forKey: .inputs)
        }
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let listed = try container.decodeIfPresent([GenerationInput].self, forKey: .inputs)
        let single = try container.decodeIfPresent(GenerationInput.self, forKey: .input)
        self.init(
            request: try container.decode(GenerationRequest.self, forKey: .request),
            inputs: listed ?? (single.map { [$0] } ?? []))
    }
}
