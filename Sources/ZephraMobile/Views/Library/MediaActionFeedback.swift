import SwiftUI

struct MediaActionFeedback: ViewModifier {
    let action: MediaAction
    func body(content: Content) -> some View {
        content
            .alert("Photos and Sharing", isPresented: Binding(
                get: { action.message != nil }, set: { if !$0 { action.message = nil } })) {
                Button("OK") { action.message = nil }
            } message: { Text(action.message ?? "") }
            .overlay {
                if action.busy { ProgressView().accessibilityLabel("Preparing media") }
            }
    }
}
