import SwiftUI

struct PromptHistorySheet: View {
    let history: MobilePromptHistory
    let select: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                if history.isLoading { ProgressView("Loading prompt history…") }
                if let failure = history.failure { Text(failure).foregroundStyle(.secondary) }
                if history.entries.isEmpty && !history.isLoading {
                    ContentUnavailableView("No Prompt History", systemImage: "clock", description: Text("Prompts appear after you generate. Auto shows connected Macs in chronological order."))
                }
                ForEach(history.entries) { entry in
                    Button {
                        select(entry.prompt); dismiss()
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(entry.prompt).foregroundStyle(.primary).lineLimit(4)
                            Text(entry.hostName + " · " + entry.createdAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .navigationTitle("Prompt History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { DismissSheetButton(title: "Done") } }
        }
    }
}
