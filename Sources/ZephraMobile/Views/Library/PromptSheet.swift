import SwiftUI
import UIKit

/// The complete saved prompt, readable and selectable without covering the image permanently.
struct PromptSheet: View {
    let entry: CachedEntry

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    LibraryHostLabel(entry: entry)
                    Text(entry.prompt)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if let negative = entry.entry.record?.negativePrompt, !negative.isEmpty {
                        Divider()
                        Text("Negative Prompt").font(.headline)
                        Text(negative).frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .font(.body)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .padding(20)
            }
            .navigationTitle("Prompt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    DismissSheetButton(title: "Done")
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Copy Prompt", systemImage: "doc.on.doc") {
                        UIPasteboard.general.string = entry.prompt
                    }
                }
            }
        }
        .presentationDragIndicator(.visible)
    }
}
