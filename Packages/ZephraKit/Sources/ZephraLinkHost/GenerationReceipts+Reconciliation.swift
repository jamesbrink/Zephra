import Foundation
import ZephraLinkProtocol

extension GenerationReceipts {
    func reconcile(active: Set<UUID>, completed: [UUID: Int], now: Date = Date()) throws {
        for (key, var receipt) in records {
            if let batch = receipt.batchID, !active.contains(batch) {
                if completed[batch, default: 0] >= (receipt.expectedCount ?? 1) { receipt.status = .completed }
                else if receipt.status == .accepted { receipt.status = .interrupted }
            }
            let terminal = receipt.status == .completed || receipt.status == .interrupted
            if terminal && now.timeIntervalSince(receipt.recordedAt) > 30 * 86_400 {
                // Keep an idempotency tombstone: expiry is never permission to enqueue again.
                receipt = GenerationReceipt(requestID: receipt.requestID, digest: receipt.digest,
                    status: .unknown, recordedAt: receipt.recordedAt)
            }
            if records[key] != receipt {
                if let root { try LinkJSON.encode(receipt).write(to: root.appendingPathComponent(key + ".json"), options: .atomic) }
                records[key] = receipt
            }
        }
    }
}

extension CompanionHost {
    func reconcileReceipts() {
        var completed: [UUID: Int] = [:]
        for item in index.items {
            if let batch = item.provenance.record?.batchID { completed[batch, default: 0] += 1 }
        }
        for (batch, count) in store.savedBatchCounts { completed[batch] = max(completed[batch, default: 0], count) }
        let active = Set(Array(store.pendingOutputBatches.values) + store.queue.map(\.batchID) + (store.running.map { [$0.batchID] } ?? []))
        do { try receipts.reconcile(active: active, completed: completed) }
        catch { logger.error("Generation receipts could not be reconciled.") }
    }
}
