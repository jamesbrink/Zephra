import SwiftUI
import ZephraStyle

/// A few of the chosen images, laid over one another like a hand of cards.
///
/// It says "several" faster than a number does, and it is honest about which several: the top
/// card is the first of the selection in the grid's own order. Three is the most that can be
/// stacked and still be told apart at this width.
struct StackedThumbnails: View {
    /// The chosen images, in the grid's order.
    let items: [LibraryItem]

    /// How many are drawn, whatever the selection's size.
    private static let shown = 3

    var body: some View {
        ZStack {
            ForEach(Array(stack.enumerated().reversed()), id: \.element.id) { depth, item in
                LibraryThumbnail(item: item)
                    .clipShape(
                        RoundedRectangle(cornerRadius: ZephraChrome.thumbnailRadius, style: .continuous)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: ZephraChrome.thumbnailRadius, style: .continuous)
                            .strokeBorder(ZephraChrome.hairline, lineWidth: 1)
                    }
                    .scaleEffect(1 - CGFloat(depth) * 0.06, anchor: .top)
                    .offset(y: CGFloat(depth) * 12)
                    .zIndex(Double(Self.shown - depth))
            }
        }
        .padding(.bottom, CGFloat(max(stack.count - 1, 0)) * 12)
        .accessibilityHidden(true)
    }

    private var stack: [LibraryItem] { Array(items.prefix(Self.shown)) }
}
