import SwiftUI
import ZephraStyle

/// The screen a phone with no Mac shows, and the only screen it shows until it has one.
///
/// Three doors, one parser. The camera above, the paste field below, and a `zephra://pair`
/// link opened from anywhere else; each hands its text to `PairingEntry.parse`, so what counts
/// as a code — and what an expired one says — is decided in one place.
struct PairingView: View {
    @Environment(MobileSession.self) private var session
    /// The last thing that went wrong, in the words to show, or nil while nothing has.
    @State private var failure: String?
    /// What is in the paste field.
    @State private var code = ""

    var body: some View {
        VStack(spacing: MobileChrome.blockSpacing) {
            Spacer(minLength: 0)
            PairingInstructions()
            if PairingScanner.isAvailable {
                PairingScanner(onScan: submit)
                    .frame(height: 260)
                    .clipShape(RoundedRectangle(cornerRadius: ZephraChrome.cardRadius))
                    .padding(.horizontal, MobileChrome.sideMargin)
            }
            PairingPasteField(code: $code) { submit(code) }
            if let failure {
                Text(failure)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, MobileChrome.sideMargin)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.canvasBackground)
        // The link door. It is handled here rather than at the root while the pairing screen
        // is up, so a code that arrives as a link is shown in the field and a bad one says why
        // in the same place a pasted one would.
        .onOpenURL { url in
            code = url.absoluteString
            submit(code)
        }
    }

    /// Reads one code and hands it on, or says what was wrong with it.
    private func submit(_ text: String) {
        do {
            let payload = try PairingEntry.parse(text)
            failure = nil
            Task {
                do { try await session.onPair(payload) } catch {
                    failure = PairingEntry.message(for: error)
                }
            }
        } catch {
            failure = PairingEntry.message(for: error)
        }
    }
}

#Preview("Pairing") {
    PairingView()
        .environment(MobileSession())
}
