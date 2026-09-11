import ZephraCore

/// One size the Size menu offers, and whether it is the shape of the picture in the well.
///
/// The Mac's `SizeChoice` in the phone's own target, deliberately: the rule is the same and
/// the numbers behind it are `ModelCapabilities`' own, but the Mac's copy lives in its app
/// target, which nothing here may reach into. What is duplicated is the shape of a menu row;
/// what is shared is every judgment under it.
struct SizeChoice: Hashable {
    /// The size the row chooses.
    var size: ImageSize
    /// Whether it is the shape of the picture in the well rather than one of the presets.
    var matchesPicture: Bool

    /// What the row says: the size, and that it is the picture's shape when it is.
    var label: String {
        matchesPicture ? "\(size.label) · Matches Picture" : size.label
    }
}
