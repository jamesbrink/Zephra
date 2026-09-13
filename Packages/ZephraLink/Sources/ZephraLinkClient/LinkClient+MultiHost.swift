import Foundation
import ZephraLinkProtocol

extension LinkClient {
    public var hostID: HostID? { pairedHost.map { HostID(keys: $0.keys) } }
    public var supportsMultiHost: Bool { snapshot?.multiHost == true }

    public func offer(_ generation: StrictGeneration, timeout: Duration = .seconds(2)) async throws -> HostOffer {
        guard supportsMultiHost else {
            throw LinkError(code: .unsupported, reason: "Update this Mac to include it in Auto.")
        }
        // Offers are advisory and time-sensitive: one short attempt, never a long request retry.
        switch try await ask(.multiHost(.offer(generation)), timeout: timeout) {
        case .multiHost(.offer(let offer)): return offer
        case .error(let error): throw error
        default: throw LinkClientError.unexpectedReply
        }
    }
    public func submit(_ generation: StrictGeneration, reference: Data?) async throws -> GenerationReceipt {
        var generation = generation
        let request = generation.request
        if let reference {
            let blob = try await sendBlob(reference, mime: "image/png")
            generation.request = GenerationRequest(modelID: request.modelID, count: request.count,
                settings: request.settings, referenceBlobID: blob, requestID: request.requestID)
        }
        switch try await negotiated(.submit(generation)) {
        case .multiHost(.receipt(let receipt)): return receipt
        case .error(let error): throw error
        default: throw LinkClientError.unexpectedReply
        }
    }
    public func receipt(_ id: UUID) async throws -> GenerationReceipt {
        switch try await negotiated(.receipt(id)) {
        case .multiHost(.receipt(let receipt)): return receipt
        case .error(let error): throw error
        default: throw LinkClientError.unexpectedReply
        }
    }
    public func setPreviews(_ enabled: Bool) async throws {
        _ = try await negotiated(.previews(enabled))
    }
    public func cancelRun(_ id: UUID) async throws {
        _ = try await negotiated(.cancelRun(id))
    }
    func listing(offset: Int, revision: String?) async throws -> LibraryListing {
        switch try await negotiated(.listing(offset: offset, limit: Self.libraryPageSize, revision: revision)) {
        case .multiHost(.listing(let listing)): return listing
        case .error(let error): throw error
        default: throw LinkClientError.unexpectedReply
        }
    }
    private func negotiated(_ command: MultiHostCommand) async throws -> Reply {
        guard supportsMultiHost else {
            throw LinkError(code: .unsupported, reason: "Update Zephra on this Mac to use Auto and targeted controls.")
        }
        let reply = try await request(.multiHost(command))
        if case .error(let error) = reply { throw error }
        return reply
    }
}
