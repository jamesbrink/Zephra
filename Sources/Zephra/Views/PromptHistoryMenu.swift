import SwiftUI
import ZephraEngine

struct PromptHistoryMenu: View {
    @Environment(GenerationStore.self) private var store
    @Environment(LibraryIndex.self) private var index
    @State private var showing = false
    var body: some View {
        Button("History", systemImage: "clock.arrow.circlepath") { showing = true }
            .buttonStyle(.plain).font(.caption).foregroundStyle(.secondary)
            .help("Up recalls older prompts; Down returns to your draft. Use arrows at the start or end of the text.")
            .popover(isPresented: $showing) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Prompt History").font(.headline)
                        Text("Use ↑ and ↓ in the prompt to recall previous requests.").font(.caption).foregroundStyle(.secondary)
                        if store.promptHistory.entries.isEmpty { Text("Your prompts appear here after Generate.").foregroundStyle(.secondary) }
                        ForEach(store.promptHistory.entries) { entry in
                            Button {
                                store.settings.prompt = entry.prompt; showing = false
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(entry.prompt).lineLimit(3).multilineTextAlignment(.leading)
                                    Text(entry.createdAt, format: .dateTime.month().day().hour().minute()).font(.caption).foregroundStyle(.secondary)
                                }.frame(maxWidth: .infinity, alignment: .leading)
                            }.buttonStyle(.plain)
                            Divider()
                        }
                    }.padding().frame(width: 350)
                }.frame(maxHeight: 450)
            }
            .task(id: index.items.count) { store.promptHistory.seed(index.items) }
    }
}
