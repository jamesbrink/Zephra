import AppKit
import SwiftUI

/// A labelled path with a button to open it in the Finder, for the folders Settings names, and
/// room after it for whatever else that folder can be done to.
///
/// The path is written the way the Finder's own Go to Folder writes it, with the home folder
/// as a tilde, so what is left after the middle truncation is the part that tells two folders
/// apart; the whole path is the tooltip, since a truncated path with no way to read the rest
/// is not a path.
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
                Text(abbreviated)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(.secondary)
                    .help(fullPath)
                Button("Open") { NSWorkspace.shared.open(directory) }
                trailing
            }
        }
    }

    private var fullPath: String { directory.path(percentEncoded: false) }

    private var abbreviated: String { (fullPath as NSString).abbreviatingWithTildeInPath }
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
