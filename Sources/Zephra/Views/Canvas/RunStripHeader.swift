import SwiftUI
import ZephraEngine

/// The rule over this run's seeds: what it is on the left, the way out on the right.
///
/// "See all in Library" clears the query as well as changing the pane. Coming to the library
/// from the canvas means "show me everything", and arriving in a view still narrowed by
/// yesterday's search would look like an empty library.
struct RunStripHeader: View {
    /// How many seeds this run has, produced and pending together.
    let seeds: Int

    @Environment(WorkspaceSelection.self) private var workspace

    var body: some View {
        HStack(spacing: 8) {
            Text("This run · \(seeds) \(seeds == 1 ? "seed" : "seeds")")
                .monospacedDigit()
            Rectangle()
                .fill(ZephraChrome.hairline)
                .frame(height: 1)
            Button("See all in Library") {
                workspace.query = LibraryQuery()
                workspace.pane = .library
            }
            .buttonStyle(.link)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .shadow(color: .black.opacity(0.55), radius: 4)
    }
}

#Preview("Header") {
    RunStripHeader(seeds: 4)
        .padding()
        .frame(width: 620)
        .background(Color.canvasBackground)
        .environment(WorkspaceSelection(pane: .canvas))
}
