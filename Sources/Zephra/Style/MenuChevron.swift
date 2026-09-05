import SwiftUI

/// The small downward chevron that says a control is a menu, for the capsule's accessory-bar
/// menus. The toolbar draws one for its own menus; inside a view `.accessoryBar` draws none
/// and `.menuIndicator(.visible)` does not add one, so the label carries it.
///
/// As a `Text` rather than a view, because a `Menu` reads its label the way `Label` does: the
/// first image is the icon, on the leading side, and any other image is dropped, so a chevron
/// drawn as a view landed in front of the title or nowhere. Inline in the title's own `Text`,
/// it sits after the words, where a chevron belongs.
enum MenuChevron {
    /// Append after the title: `Text("1024 × 1024") + MenuChevron.text`.
    static let text: Text = Text(" ") + Text(Image(systemName: "chevron.down"))
        .font(.caption2.weight(.semibold))
        .foregroundStyle(.secondary)
}

#Preview("Chevron") {
    (Text("1024 × 1024").font(.callout) + MenuChevron.text)
        .padding()
}
