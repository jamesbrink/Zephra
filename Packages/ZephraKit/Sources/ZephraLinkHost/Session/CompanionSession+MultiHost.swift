import Foundation
import ZephraCore
import ZephraEngine
import ZephraLinkProtocol

extension CompanionSession {
    /// Solicited capability use is the phone's opt-in. Legacy sessions see no new events.
    func performMultiHost(_ command: MultiHostCommand, on host: CompanionHost) throws -> Reply {
        switch command {
        case .previews(let enabled):
            wantsPreviews = enabled
            if !enabled { pendingPreview = nil }
            return .ok
        case .cancelRun(let id):
            host.store.cancelRun(id)
            return .ok
        case .offer(let strict):
            return .multiHost(.offer(try offer(strict, on: host)))
        case .submit(let strict):
            return try submitStrict(strict, on: host)
        case .receipt(let id):
            host.reconcileReceipts()
            guard let peer else { throw LinkError.notPaired }
            let receipt = try host.receipts.read(peer: peer, request: id)
            return .multiHost(.receipt(receipt ?? GenerationReceipt(
                requestID: id, digest: "", status: .unknown)))
        case .listing(let offset, let limit, let expected):
            let items = LibraryEntryProjection.listing(host.index.items)
            let entries = items.map(LibraryEntryProjection.entry)
            let revision = GenerationInput.digest(try LinkJSON.encode(entries))
            if let expected, expected != revision {
                throw LinkError(code: .busy, reason: "The library changed. Read it again.")
            }
            return .multiHost(.listing(LibraryListing(revision: revision,
                page: LibraryEntryProjection.page(items, offset: offset, limit: min(max(limit, 1), 100)))))
        }
    }

    private func submitStrict(_ strict: StrictGeneration, on host: CompanionHost) throws -> Reply {
        guard let peer else { throw LinkError.notPaired }
        let request = strict.request
        let digest = try strict.digest()
        if let receipt = try host.receipts.read(peer: peer, request: request.requestID) {
            guard receipt.digest == digest else {
                throw LinkError(code: .badRequest, reason: "That request ID already names different work.")
            }
            return .multiHost(.receipt(receipt))
        }
        // Past the ledger, so this refusal is only ever a fresh ask, and a repeat of a submit
        // this Mac accepted has already been answered with the receipt above. Here rather than
        // at the door of `perform` for that reason: below this line the work would be written
        // as `.prepared` and then turned away by `enqueue`, which is one work named twice — the
        // sentence and a receipt frozen at `unknown`.
        guard !host.store.deviceLost else {
            throw LinkError(code: .refused, reason: EngineError.deviceLost.message)
        }
        let assessment = try offer(strict, on: host)
        if let refusal = assessment.refusal { throw LinkError(code: .refused, reason: refusal) }
        var settings = request.settings
        settings.referenceImages = try takeReferences(
            named: request.referenceBlobIDs, matching: strict.inputs, for: settings)
        let model = try Self.model(request.modelID)
        if let refusal = host.store.strictRefusal(for: model, settings: settings, count: request.count) {
            throw LinkError(code: .refused, reason: refusal)
        }
        let batch = UUID()
        // The prepared record lands before any work. A crash in the following window is unknown.
        var prepared = GenerationReceipt(requestID: request.requestID,
            digest: digest, batchID: batch, status: .prepared)
        prepared.expectedCount = request.count
        try host.receipts.write(prepared, peer: peer)
        guard host.store.enqueue(settings, on: model, count: request.count,
            batchID: batch, requiresInstalledModel: true) != nil else {
            return .multiHost(.receipt(GenerationReceipt(requestID: request.requestID,
                digest: digest, batchID: batch, status: .unknown)))
        }
        var receipt = GenerationReceipt(requestID: request.requestID, digest: digest,
            batchID: batch, status: .accepted)
        receipt.expectedCount = request.count
        // A disk error after enqueue must never be reported as non-acceptance.
        do { try host.receipts.write(receipt, peer: peer) } catch {
            return .multiHost(.receipt(GenerationReceipt(requestID: request.requestID,
                digest: digest, batchID: batch, status: .prepared)))
        }
        return .multiHost(.receipt(receipt))
    }
}
