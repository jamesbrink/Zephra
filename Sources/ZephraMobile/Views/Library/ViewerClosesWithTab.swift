import SwiftUI

/// Closes the viewer when the surface it was opened over stops being the one showing.
///
/// A full-screen cover belongs to the tab that presented it, and a `TabView` keeps every tab
/// alive, so moving `MobileSelection.tab` from inside the viewer — "Use as Reference" sends
/// somebody to the canvas — moved the tab *underneath* the cover and left the viewer standing
/// over the canvas it was meant to reveal. The viewer hides the tab bar, so nothing but a press
/// inside it moves the tab while it is up, and whatever does wants what is under it seen.
///
/// The closing is the environment's `dismiss`, the one the Close button and the pull call, so
/// there is one way the viewer goes away. The rule is on the viewer rather than on each button
/// that moves the tab, so a press from a cell in the grid, where there is no viewer, changes
/// nothing it did not before.
struct ViewerClosesWithTab: ViewModifier {
    @Environment(MobileSelection.self) private var selection
    @Environment(\.dismiss) private var dismiss
    /// The tab showing when the viewer went up.
    @State private var openedOver: MobileTab?

    func body(content: Content) -> some View {
        content
            .onAppear { openedOver = openedOver ?? selection.tab }
            .onChange(of: selection.tab) { _, now in
                if Self.closes(openedOver: openedOver, now: now) { dismiss() }
            }
    }

    /// Whether the viewer should close, given the tab it opened over and the one showing now.
    static func closes(openedOver: MobileTab?, now: MobileTab) -> Bool {
        guard let openedOver else { return false }
        return now != openedOver
    }
}
