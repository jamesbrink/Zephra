/// What the user asked for about the tiled VAE decode.
///
/// The trade the setting makes: tiling cuts several gigabytes off the peak at 1024 pixels, and
/// the image comes back differing by about one part in 255 with no visible seam. Exactness is
/// the default where a Mac has the memory for it, which is what `automatic` works out.
public enum VAETilingMode: String, CaseIterable, Hashable, Sendable {
    /// Tile only when the chosen model would otherwise page on this Mac.
    case automatic
    /// Always tile, whatever the machine.
    case always
    /// Never tile: the decode stays exact, even where that means swapping.
    case never

    /// How the setting reads in a picker.
    public var displayName: String {
        switch self {
        case .automatic: "Automatic"
        case .always: "Always"
        case .never: "Never"
        }
    }
}
