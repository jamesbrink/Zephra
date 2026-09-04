import AppKit
import SwiftUI

/// A labelled path with a button to open it in the Finder, for the folders Settings names, and
/// room after it for whatever else that folder can be done to.
struct DirectoryRow<Trailing: View>: View {
    let label: String
    let directory: URL
    @ViewBuilder let trailing: Trailing

    init(_ label: String, _ directory: URL, @ViewBuilder trailing: () -> Trailing) {
        self.label = label
        self.directory = directory
        self.trailing = trailing()
    }

    var body: some View {
        LabeledContent(label) {
            HStack {
                Text(directory.path(percentEncoded: false))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(.secondary)
                Button("Open") { NSWorkspace.shared.open(directory) }
                trailing
            }
        }
    }
}

extension DirectoryRow where Trailing == EmptyView {
    /// A folder there is nothing to do to but look at it.
    init(_ label: String, _ directory: URL) {
        self.init(label, directory) { EmptyView() }
    }
}

#Preview("Directory") {
    Form {
        DirectoryRow("Images are saved to", URL.picturesDirectory.appending(path: "Zephra"))
    }
    .formStyle(.grouped)
    .frame(width: 480)
}
