import SwiftUI

/// The picker's own search field, styled like `SidebarSearch` but bound to the sheet's own
/// text rather than the window's query — the two searches are unrelated, and typing here must
/// never narrow the library grid behind the sheet.
///
/// Focused as soon as it appears, since the sheet opens with nothing chosen and typing is the
/// first thing a picker like this is for. A down arrow hands the keyboard to the grid below,
/// so the field and the grid walk as one list.
struct ReferencePickerSearch: View {
    /// What is typed, and what filtering it does; shared with the grid below.
    let selection: ReferencePickerSelection

    @FocusState private var isFocused: Bool

    var body: some View {
        @Bindable var selection = selection
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.caption)
                .foregroundStyle(.tertiary)
            TextField("Search prompts and seeds", text: $selection.text)
                .textFieldStyle(.plain)
                .font(.callout)
                .focused($isFocused)
                .onKeyPress(.downArrow) {
                    selection.gridFocusRequests += 1
                    return .handled
                }
        }
        .padding(.horizontal, 8)
        .frame(height: 26)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .task { isFocused = true }
        .accessibilityLabel("Search the library")
    }
}

#Preview("Search") {
    ReferencePickerSearch(selection: ReferencePickerSelection())
        .padding()
        .frame(width: 280)
}
