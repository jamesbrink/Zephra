import AppKit
import SwiftUI

/// A labelled path with a button to open it in the Finder, for the folders Settings names.
struct DirectoryRow: View {
    let label: String
    let directory: URL

    init(_ label: String, _ directory: URL) {
        self.label = label
        self.directory = directory
    }

    var body: some View {
        LabeledContent(label) {
            HStack {
                Text(directory.path(percentEncoded: false))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(.secondary)
                Button("Open") { NSWorkspace.shared.open(directory) }
            }
        }
    }
}

#Preview("Directory") {
    Form {
        DirectoryRow("Images are saved to", URL.picturesDirectory.appending(path: "Zephra"))
    }
    .formStyle(.grouped)
    .frame(width: 480)
}
