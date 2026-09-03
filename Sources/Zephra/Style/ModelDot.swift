import SwiftUI

/// The coloured mark beside a model's name, so a row in the sidebar and a badge on a thumbnail
/// are recognisably the same model without either of them spelling it out.
struct ModelDot: View {
    /// The `ModelDescriptor` identifier whose colour to show.
    let modelID: String

    /// A dot for one model.
    init(_ modelID: String) {
        self.modelID = modelID
    }

    var body: some View {
        Circle()
            .fill(Color.modelDot(modelID))
            .frame(width: 8, height: 8)
    }
}

#Preview("Dots") {
    VStack(alignment: .leading, spacing: 6) {
        ForEach(["z-image-turbo-8bit", "z-image-turbo-4bit", "qwen-image-2512-4bit", "flux"], id: \.self) { id in
            HStack(spacing: 8) {
                ModelDot(id)
                Text(id)
            }
        }
    }
    .font(.callout)
    .padding(24)
}
