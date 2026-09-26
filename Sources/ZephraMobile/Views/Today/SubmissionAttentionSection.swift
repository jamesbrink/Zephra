import SwiftUI

struct SubmissionAttentionSection: View {
    @Environment(GenerationDispatch.self) private var dispatch
    var body: some View {
        let records = SubmissionAttention.visible(dispatch.submissions)
        if !records.isEmpty {
            Section("Needs Attention") {
                ForEach(records) { submission in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(submission.generation.request.settings.prompt).lineLimit(2)
                        Text(submission.hostName + " · " + label(submission.state))
                            .font(.caption).foregroundStyle(.secondary)
                        if let note = submission.note { Text(note).font(.caption).foregroundStyle(.secondary) }
                        Text(submission.createdAt, format: .dateTime.hour().minute()).font(.caption2).foregroundStyle(.tertiary)
                    }
                }
            }
        }
    }
    private func label(_ state: Submission.State) -> String {
        switch state {
        case .unknown: "Checking submission · may already be running"
        case .sending: "Sending request"
        case .interrupted: "Interrupted"
        case .rejected: "Request refused"
        case .accepted, .completed: ""
        }
    }
}
