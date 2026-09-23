/// The sizes ⌘+ and ⌘− step the library's thumbnails through when no picture is up to zoom.
///
/// The slider is continuous and these are not, deliberately: a keystroke should land on a size
/// that is already in the cache rather than somewhere between two of them, so holding ⌘+ walks
/// the whole range instantly instead of baking a fresh set at each of a dozen widths.
///
/// The largest bucket is bigger than the slider goes, so the steps are clamped to what the
/// slider can actually show — a shortcut must never put the interface somewhere the control
/// beside it cannot represent.
enum ThumbnailSizeSteps {
    /// Every bucket, clamped into the slider's range.
    static let all: [Double] = {
        let ceiling = AppSettings.libraryThumbnailEdgeBounds.upperBound
        var steps: [Double] = []
        for size in ThumbnailSize.allCases {
            let clamped = min(Double(size.points), ceiling)
            if steps.last != clamped { steps.append(clamped) }
        }
        return steps
    }()

    /// The next size up from `edge`, or nil at the largest.
    static func bigger(than edge: Double) -> Double? { all.first { $0 > edge } }

    /// The next size down from `edge`, or nil at the smallest.
    static func smaller(than edge: Double) -> Double? { all.last { $0 < edge } }
}
