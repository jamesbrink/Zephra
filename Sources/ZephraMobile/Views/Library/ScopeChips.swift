import SwiftUI
import ZephraStyle

/// All, Favorites, Clips: which collection of the library is on screen.
///
/// `Chip` from the shared chrome rather than a segmented control, so the phone's scopes and the
/// Mac's sidebar scopes are recognisably the same thing. Three across a phone, which is why
/// there are three of them — see `CachedScope`.
struct ScopeChips: View {
    @Environment(LibraryCatalog.self) private var catalog
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        if typeSize.isAccessibilitySize {
            @Bindable var catalog = catalog
            Picker("Library collection", selection: $catalog.query.scope) {
                ForEach(CachedScope.allCases) { scope in Text(scope.title).tag(scope) }
            }
            .pickerStyle(.menu)
            .padding(.horizontal, MobileChrome.sideMargin)
        } else { chips }
    }
    private var chips: some View {
        HStack(spacing: 6) {
            ForEach(CachedScope.allCases) { scope in
                Button { catalog.query.scope = scope } label: {
                    Chip(scope.title, isSelected: catalog.query.scope == scope)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(catalog.query.scope == scope ? .isSelected : [])
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, MobileChrome.sideMargin)
        .padding(.vertical, 8)
    }
}

#Preview("Scopes") {
    ScopeChips()
        .environment(LibraryCatalog(libraryRoot: nil, filesRoot: nil))
}
