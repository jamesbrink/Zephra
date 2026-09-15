import SwiftUI
import UIKit

/// Local actions work from cached provenance, even while the source Mac is offline.
struct GenerationActions: View {
    let entry: CachedEntry
    @Environment(\.reuseImageSettings) private var reuse

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ViewPromptButton(entry: entry)
        Button("Copy Prompt", systemImage: "doc.on.doc") {
            UIPasteboard.general.string = entry.prompt
        }
        .disabled(entry.prompt.isEmpty)
        Button("Reuse Settings", systemImage: "arrow.counterclockwise") {
            reuse(entry)
            dismiss()
        }
        .disabled(entry.entry.record == nil)
    }
}

extension EnvironmentValues {
    @Entry var reuseImageSettings: (CachedEntry) -> Void = { _ in }
}
