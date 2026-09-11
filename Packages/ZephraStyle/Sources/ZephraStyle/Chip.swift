import SwiftUI

/// A small rounded label: a scope in the sidebar, a tag, a token over the library grid.
///
/// Never accent-coloured and never amber. Amber means the model is working, and a chip that
/// borrowed it would say so falsely; a selected chip is a lighter neutral instead, which is
/// what the system's own segmented controls do.
public struct Chip: View {
    /// The word on it.
    public let title: String
    /// Whether it is the one currently chosen.
    public let isSelected: Bool
    /// What to do when its cross is pressed, or nil for a chip that cannot be removed.
    public let onRemove: (() -> Void)?

    /// A chip, removable only if a `onRemove` is given.
    public init(_ title: String, isSelected: Bool = false, onRemove: (() -> Void)? = nil) {
        self.title = title
        self.isSelected = isSelected
        self.onRemove = onRemove
    }

    public var body: some View {
        HStack(spacing: 4) {
            Text(title)
                .lineLimit(1)
            if let onRemove {
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tertiary)
                .accessibilityLabel("Remove \(title)")
            }
        }
        .font(.callout)
        .foregroundStyle(isSelected ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
        .padding(.horizontal, 9)
        .frame(height: 22)
        .background(
            isSelected ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.quaternary),
            in: RoundedRectangle(cornerRadius: ZephraChrome.chipRadius, style: .continuous)
        )
    }
}

#Preview("Chips") {
    HStack(spacing: 6) {
        Chip("All", isSelected: true)
        Chip("Favorites")
        Chip("Qwen")
        Chip("street at night") {}
    }
    .padding(24)
}
