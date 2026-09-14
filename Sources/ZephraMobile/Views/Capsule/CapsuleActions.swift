import SwiftUI

/// Batch size and generation each have room to grow with the text.
struct CapsuleActions: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CountControl()
            GenerateButton()
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }
}
