import SwiftUI

/// An explicit image target that remains legible over the floating capsule's material.
struct ReferencePlaceholder: View {
    var body: some View {
        VStack(spacing: 5) {
            Image(systemName: "photo.badge.plus")
                .font(.title2)
            Text("Reference")
                .font(.caption2)
        }
        .foregroundStyle(.primary)
        .frame(width: 64, height: 64)
        .background(Color(nsColor: .controlBackgroundColor), in: shape)
        .overlay { shape.strokeBorder(.secondary, lineWidth: 1) }
        .contentShape(shape)
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: ZephraChrome.cardRadius, style: .continuous)
    }
}
