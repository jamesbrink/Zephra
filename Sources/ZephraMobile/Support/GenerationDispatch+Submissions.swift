import Foundation
import ZephraLinkClient
import ZephraLinkProtocol

extension GenerationDispatch {
    func send(_ generation: StrictGeneration, reference: Data?) async {
        guard !isSending else { return }
        isSending = true; note = nil
        defer { isSending = false }
        await refresh(generation, forSubmission: true)
        guard let host = target, host.preference.enabled, host.client.connection.isLive, host.client.hasFreshSnapshot else {
            note = "No connected Mac can take this job."; return
        }
        if destination == nil && offers[host.id]?.refusal != nil { note = reason; return }
        var submission = Submission(generation: generation, hostID: host.id, hostName: host.name,
            state: .sending, createdAt: Date())
        do { try record(submission) } catch { note = "The submission could not be saved. Nothing was sent."; return }
        do {
            if host.client.supportsMultiHost {
                let receipt = try await host.client.submit(generation, reference: reference)
                submission.batchID = receipt.batchID
                submission.state = Self.state(receipt.status)
            } else {
                submission.batchID = try await host.client.enqueue(generation.request, reference: reference)
                submission.state = .accepted
            }
            note = submission.state == .accepted ? "Queued on \(host.name)" : "Checking submission on \(host.name)"
        } catch let error as LinkError {
            submission.state = .rejected; submission.note = error.reason; note = error.reason
        } catch {
            submission.state = .unknown
            note = "Checking submission on \(host.name). It may already be running."
        }
        do { try record(submission) } catch { note = "Submission sent; its saved status is uncertain. Check \(host.name)." }
    }
    func reconcile() async {
        for var submission in submissions where submission.state == .unknown || submission.state == .sending || submission.state == .accepted {
            guard let host = hosts.hosts.first(where: { $0.id == submission.hostID }), host.client.connection.isLive,
                  let receipt = try? await host.client.receipt(submission.id) else { continue }
            submission.state = Self.state(receipt.status); submission.batchID = receipt.batchID
            try? record(submission)
        }
    }
    static func state(_ status: GenerationReceipt.Status) -> Submission.State {
        switch status {
        case .accepted: .accepted
        case .completed: .completed
        case .interrupted: .interrupted
        case .unknown, .prepared: .unknown
        }
    }
    func record(_ submission: Submission) throws {
        var next = submissions.filter { $0.id != submission.id }
        next.append(submission)
        if let root {
            try CacheDirectories.prepare(root.deletingLastPathComponent())
            try LinkJSON.encode(next).write(to: root, options: .atomic)
        }
        publish(next)
    }
}
