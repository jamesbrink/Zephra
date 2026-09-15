import SwiftUI
import ZephraLinkProtocol

/// Report acknowledgment and failures from the presenting surface, after its menu closes.
struct UpscaleRequests: ViewModifier {
    @Environment(LibraryCatalog.self) private var catalog
    @State private var result: String?
    @State private var isSending = false

    func body(content: Content) -> some View {
        content
            .environment(\.upscaleLibraryImage) { entry, factor in
                guard !isSending else { return }
                isSending = true
                Task {
                    defer { isSending = false }
                    do {
                        try await catalog.upscale(entry, factor: factor)
                        result = "Your Mac started the \(factor)× upscale. The larger image will appear in Library when it finishes."
                    } catch let error as LinkError {
                        result = error.reason
                    } catch {
                        result = "The upscale could not be confirmed. Check the source Mac or Library before trying again."
                    }
                }
            }
            .alert("Upscale", isPresented: Binding(
                get: { result != nil }, set: { if !$0 { result = nil } })
            ) {
                Button("OK") { result = nil }
            } message: {
                Text(result ?? "")
            }
    }
}
