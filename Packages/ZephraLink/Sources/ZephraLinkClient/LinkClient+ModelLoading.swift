import Foundation
import ZephraLinkProtocol

/// Loading and unloading the Mac's model from the phone.
///
/// Gated on a snapshot flag rather than the protocol version, which the handshake requires both
/// ends to match on exactly and so can never say what one end alone can do. A Mac without the
/// flag is never sent either command: there the phone shows neither control, and the widened
/// `canQueue` on a newer Mac is what makes Generate alone enough to recover from a fault.
extension LinkClient {
    /// Whether this Mac understands the two commands below and stamps `loadedModelID`.
    public var supportsModelLoading: Bool {
        hasFreshSnapshot && snapshot?.modelLoading == true
    }

    /// Chooses `modelID` if it is not already chosen and reads its weights in now.
    ///
    /// Repeatable, so it takes `request`'s own retry: asking twice for the model that is
    /// already loading is a no-op the Mac answers `.ok` to.
    public func loadModel(_ modelID: String) async throws {
        guard supportsModelLoading else {
            throw LinkError(code: .unsupported, reason: "Update Zephra on this Mac to load models from here.")
        }
        try await perform(.loadModel(modelID))
    }

    /// Gives the Mac's weights back, leaving the chosen model chosen.
    public func unloadModel() async throws {
        guard supportsModelLoading else {
            throw LinkError(code: .unsupported, reason: "Update Zephra on this Mac to unload models from here.")
        }
        try await perform(.unloadModel)
    }

    /// A command whose only good answer is that it was done.
    private func perform(_ command: Command) async throws {
        switch try await request(command) {
        case .multiHost, .ok, .queued, .blob, .entries: return
        case .error(let error): throw error
        }
    }
}
