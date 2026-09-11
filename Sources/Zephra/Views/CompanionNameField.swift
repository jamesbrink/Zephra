import SwiftUI

/// What this Mac calls itself on a phone's list of Macs.
///
/// Empty means the machine's own name, which is what the prompt shows, so a person who has
/// never touched this row still sees something they recognize and a person who clears the field
/// gets that back rather than a nameless Mac.
struct CompanionNameField: View {
    @AppStorage(AppSettings.companionDeviceName) private var name = ""

    var body: some View {
        TextField("Name on the phone", text: $name, prompt: Text(AppSettings.companionName()))
    }
}

#Preview("Name") {
    Form { CompanionNameField() }
        .formStyle(.grouped)
        .frame(width: 480)
}
