import SwiftUI

/// The line above a group of things: what the group is, optionally how many, and one action.
///
/// It sets no font of its own. A header in the sidebar and a header over the library grid are
/// different sizes, and the call site is the only place that knows which it is.
struct SectionHeader<Trailing: View>: View {
    /// What the group is.
    let title: String
    /// A count or a note beside the title, or nil for a bare header.
    let detail: String?
    /// The one action the group offers, at the far end.
    let trailing: Trailing

    /// A header with an action after it.
    init(_ title: String, detail: String? = nil, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.detail = detail
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
                .foregroundStyle(.secondary)
            if let detail {
                Text(detail)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }
            Spacer(minLength: 8)
            trailing
        }
        .lineLimit(1)
    }
}

extension SectionHeader where Trailing == EmptyView {
    /// A header with nothing after it.
    init(_ title: String, detail: String? = nil) {
        self.init(title, detail: detail) { EmptyView() }
    }
}

#Preview("Headers") {
    VStack(alignment: .leading, spacing: 12) {
        SectionHeader("Queue") {
            Button("Clear") {}
                .buttonStyle(.link)
        }
        SectionHeader("Today", detail: "14")
        SectionHeader("Models")
    }
    .font(.caption)
    .fontWeight(.semibold)
    .padding(24)
    .frame(width: 260)
}
