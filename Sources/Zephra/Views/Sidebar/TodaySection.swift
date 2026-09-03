import SwiftUI

/// Where today's images will sit, in two columns, once there is a library index to read them
/// from. A placeholder until then, and a deliberate one: the section exists so the sidebar's
/// height and scroll behaviour are settled before it is filled in.
struct TodaySection: View {
    var body: some View {
        Section("Today") {
            Text("Today's images appear here.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
                .listRowBackground(Color.clear)
        }
    }
}

#Preview("Today") {
    List {
        TodaySection()
    }
    .listStyle(.sidebar)
    .frame(width: 280, height: 140)
}
