import SwiftUI
import ZephraCore
import ZephraEngine
import ZephraStyle

/// Every model the catalog knows, as cards: what each one makes, what it downloads, and how it
/// would run on this Mac. The way to a model the pull-down does not list, because the pull-down
/// lists what is here.
///
/// The same card grid the first-launch chooser draws (`ModelChoiceGrid`), and deliberately not
/// the same screen. `WelcomeView` carries layout that exists for the full-window case alone —
/// the two spacers that centre it, the 1040-point content column, two pinned screenshots — and
/// sharing a body would make this sheet's fixed frame the thing that decides the chooser's
/// layout. One grid, two hosts, two chromes.
struct ModelBrowserSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            ModelBrowserHeader()
            Divider()
            ModelBrowserList()
        }
        // Wider than the reference picker's 640: the grid's columns are 280 at their narrowest
        // with 16 of spacing and 64 of padding, which is 640 exactly and would collapse to one
        // column the moment a scroller appeared. 760 gives two columns with room and stays
        // under the window's own 880-point floor, so the sheet never overhangs its window.
        .frame(width: 760, height: 560)
        .onExitCommand { dismiss() }
    }
}

#Preview("Models") {
    Color.clear
        .frame(width: 900, height: 700)
        .sheet(isPresented: .constant(true)) {
            ModelBrowserSheet()
                .environment(GenerationStore.preview(state: .idle))
                .environment(\.memoryBudget, MemoryBudget(physicalMemory: 16 << 30))
        }
}
