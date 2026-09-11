import SwiftUI
import ZephraLinkHost
import ZephraLinkProtocol
import ZephraStyle

/// The code a phone reads to pair with this Mac, and the two minutes it is good for.
///
/// The countdown is `Text`'s own timer style rather than anything that ticks here: the app
/// target runs no repeating animation, and a system-drawn label counting down to a date is
/// exactly the case that rule is not about.
///
/// The code is drawn once per payload in a `task`, not in `body`: Core Image on five hundred
/// characters is cheap but not free, and `body` runs whenever anything in Settings moves.
struct PairingQRView: View {
    /// How wide the code is drawn. Big enough for a phone's camera across a desk, small enough
    /// to leave the list of devices on screen under it.
    static let edge: CGFloat = 240

    @Environment(CompanionHost.self) private var host: CompanionHost?
    @State private var code: NSImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let payload = host?.pairing {
                live(payload)
            } else {
                Button("Show a Pairing Code") { _ = host?.beginPairing() }
                    .disabled(host == nil)
                Text("Open Zephra on your iPhone and point it at the code.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task(id: host?.pairing) { code = Self.draw(host?.pairing) }
    }

    /// The code on screen, with what is left of its two minutes under it.
    @ViewBuilder
    private func live(_ payload: PairingPayload) -> some View {
        if let code {
            Image(nsImage: code)
                .interpolation(.none)
                .frame(width: Self.edge, height: Self.edge)
                .clipShape(RoundedRectangle(cornerRadius: ZephraChrome.cardRadius, style: .continuous))
                .accessibilityLabel("Pairing code for \(payload.hostName)")
        }
        HStack(spacing: 8) {
            Text("This code stops working in")
            Text(payload.expiresAt, style: .timer)
                .monospacedDigit()
            Spacer()
            Button("Stop") { host?.endPairing() }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    /// One payload as a picture, or nil when there is no payload or it will not encode.
    private static func draw(_ payload: PairingPayload?) -> NSImage? {
        guard let payload, let link = try? PairingURL.encode(payload) else { return nil }
        return PairingQRCode.image(for: link.absoluteString, points: edge)
    }
}

#Preview("Pairing") {
    Form { PairingQRView() }
        .formStyle(.grouped)
        .frame(width: 520, height: 420)
}
