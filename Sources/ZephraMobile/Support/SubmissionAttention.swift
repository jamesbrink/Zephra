import Foundation

/// Receipts are durable bookkeeping, not a second gallery of completed jobs.
enum SubmissionAttention {
    static func visible(_ submissions: [Submission], now: Date = Date(), calendar: Calendar = .current) -> [Submission] {
        submissions.filter {
            switch $0.state {
            case .unknown, .sending: true
            case .interrupted, .rejected: calendar.isDate($0.createdAt, inSameDayAs: now)
            case .accepted, .completed: false
            }
        }.sorted { $0.createdAt > $1.createdAt }
    }
}
