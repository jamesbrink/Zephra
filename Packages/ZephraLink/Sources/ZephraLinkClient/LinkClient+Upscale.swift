import ZephraLinkProtocol

extension LinkClient {
    /// An upscale starts work. Do not repeat it automatically if its acknowledgment is lost:
    /// an older Mac has no request identifier with which to recognize the same upscale.
    public func upscale(name: String, factor: Int) async throws {
        let reply = try await request(.upscale(name: name, factor: factor))
        if case .error(let error) = reply { throw error }
        guard case .ok = reply else { throw LinkClientError.unreachable }
    }
}
