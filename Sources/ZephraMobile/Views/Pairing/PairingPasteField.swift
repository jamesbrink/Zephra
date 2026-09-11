import SwiftUI
import ZephraStyle

/// The door that is always open: a field to paste a pairing code into, and a button to send it.
///
/// Always shown, never conditional on the camera. The simulator has no camera, VoiceOver users
/// should not have to aim one, and a code can arrive by message as easily as on a screen — so
/// the typed path is the one that must always work, and the scanner is the shortcut above it.
struct PairingPasteField: View {
    /// The text as typed or pasted. Held by `PairingView`, because that is what submits it.
    @Binding var code: String
    /// What to do with it.
    let submit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Pairing code", text: $code, axis: .vertical)
                .textFieldStyle(.plain)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .lineLimit(1...3)
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: ZephraChrome.fieldRadius)
                        .fill(ZephraChrome.wellFill))
                .accessibilityLabel("Pairing code")
            // The width goes on the label, not on the button: a frame outside a bordered
            // button stretches the space it sits in and leaves the capsule its own small size
            // in the middle of it, which is what the first screenshot of this screen showed.
            Button(action: submit) {
                Text("Pair").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, MobileChrome.sideMargin)
    }
}

#Preview("Paste field") {
    PairingPasteField(code: .constant("zephra://pair?v=1&d=abc"), submit: {})
}
