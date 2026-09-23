import Foundation
import ZephraLinkProtocol

extension LinkClient {
    public var hostID: HostID? { pairedHost.map { HostID(keys: $0.keys) } }
    public var hasFreshSnapshot: Bool { isFrozen || session?.hasSnapshot == true }
    public var authenticatedSessionID: UUID? { hasFreshSnapshot ? session?.id : nil }
    public var supportsMultiHost: Bool { hasFreshSnapshot && snapshot?.multiHost == true }

    public func offer(_ generation: StrictGeneration, timeout: Duration = .seconds(2)) async throws -> HostOffer {
        guard supportsMultiHost else {
            throw LinkError(code: .unsupported, reason: "Update this Mac to include it in Auto.")
        }
        // Offers are advisory and time-sensitive: one short attempt, never a long request retry.
        switch try await ask(.multiHost(.offer(generation)), timeout: timeout) {
        case .multiHost(.offer(var offer)):
            offer.requiresInputTransfer = generation.inputs.isEmpty ? nil : true
            let bytes = generation.inputs.reduce(0) { $0 + $1.byteCount }
            offer.inputTransferSeconds = bytes == 0
                ? nil : session?.uploadTimings.estimate(bytes: bytes)
            return offer
        case .error(let error): throw error
        default: throw LinkClientError.unexpectedReply
        }
    }
    public func submit(_ generation: StrictGeneration, reference: Data?) async throws -> GenerationReceipt {
        try await submit(generation, references: reference.map { [$0] } ?? [])
    }

    /// The same, for a model that reads several pictures: each crosses as a blob of its own, in
    /// the order the declared inputs are in, and the request names them in that order.
    public func submit(
        _ generation: StrictGeneration, references: [Data]
    ) async throws -> GenerationReceipt {
        let started = ContinuousClock.now
        let owner = session
        var generation = generation
        let request = generation.request
        if !references.isEmpty {
            var blobIDs: [UUID] = []
            for reference in references {
                blobIDs.append(try await sendBlob(reference, mime: "image/png"))
            }
            generation.request = GenerationRequest(modelID: request.modelID, count: request.count,
                settings: request.settings, referenceBlobIDs: blobIDs, requestID: request.requestID)
        }
        switch try await negotiated(.submit(generation)) {
        case .multiHost(.receipt(let receipt)):
            let bytes = references.reduce(0) { $0 + $1.count }
            if bytes > 0, let owner, session === owner {
                let elapsed = ContinuousClock.now - started
                let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
                owner.uploadTimings.record(bytes: bytes, seconds: seconds)
            }
            return receipt
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
    public func setPreviews(_ enabled: Bool, timeout: Duration = .seconds(2)) async throws {
        _ = try await negotiated(.previews(enabled), timeout: timeout)
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
    private func negotiated(_ command: MultiHostCommand, timeout: Duration? = nil) async throws -> Reply {
        guard supportsMultiHost else {
            throw LinkError(code: .unsupported, reason: "Update Zephra on this Mac to use Auto and targeted controls.")
        }
        let reply: Reply
        if let timeout { reply = try await ask(.multiHost(command), timeout: timeout) }
        else { reply = try await request(.multiHost(command)) }
        if case .error(let error) = reply { throw error }
        return reply
    }
}
