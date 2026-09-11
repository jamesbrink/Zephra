import SwiftUI

/// Which build of the phone app this is.
///
/// Read from the bundle rather than written down, so it is the build that is running and not
/// the build somebody remembered to update a constant for. The Mac's About window is the same
/// two numbers in the same order; a person reading one to somebody over the phone should not
/// have to work out which is which.
struct AboutRow: View {
    var body: some View {
        LabeledContent("Version", value: Self.version)
    }

    /// The marketing version and the build, as "0.1.0 (202609111530)".
    static var version: String {
        let info = Bundle.main.infoDictionary
        let marketing = info?["CFBundleShortVersionString"] as? String ?? "0.0.0"
        guard let build = info?["CFBundleVersion"] as? String else { return marketing }
        return "\(marketing) (\(build))"
    }
}

#Preview("About") {
    Form { AboutRow() }
}
