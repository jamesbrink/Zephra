import SwiftUI

/// What to do on the Mac before anything here will work.
///
/// Its own view rather than three `Text`s inside `PairingView`, because these are the words a
/// person reads while holding a phone in one hand and looking at a Mac: they get changed on
/// their own, and they should be findable on their own.
struct PairingInstructions: View {
    var body: some View {
        VStack(spacing: 8) {
            Text("Pair with your Mac")
                .font(.title2.weight(.semibold))
            Text(
                """
                Open Zephra on your Mac, choose Settings > Companion, and point this phone \
                at the code, or paste it below.
                """
            )
            .font(.callout)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
        }
        .padding(.horizontal, MobileChrome.sideMargin)
    }
}

#Preview("Instructions") {
    PairingInstructions()
}
