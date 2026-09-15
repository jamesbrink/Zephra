import ZephraCore

/// What the model browser's one button does for the card that is selected.
///
/// Pure, so the five answers and their words are tested without a sheet. Every one of them is
/// Title Case, as a push button is, and a model this Mac cannot hold says what it would take
/// rather than offering a transfer that is never going to start.
enum ModelBrowserAction: Hashable {
    /// The files are not here: fetch them, and nothing else.
    case download(bytes: Int64)
    /// The release is here and the variant is not: the same door, which builds as it acquires.
    case build
    /// The model is here and is not the one chosen: choose it.
    case use
    /// The model is here and chosen and not in: read its weights in.
    case load
    /// The model is here, chosen and in. There is nothing left to do.
    case done
    /// Nothing may be pressed, for the reason given.
    case unavailable(String)

    /// The action for one card, from the disk's answer and this Mac's memory.
    ///
    /// Memory is asked first: a model this Mac cannot hold is out whatever the disk says, and
    /// "Download 13.3 GB" over a disabled button would offer a transfer nothing will load.
    static func action(
        availability: ModelAvailability?,
        fit: MemoryFit,
        isChosen: Bool,
        isLoaded: Bool
    ) -> ModelBrowserAction {
        guard fit.isSelectable else {
            return .unavailable(fit.label ?? "Needs More Memory")
        }
        switch availability {
        case .missing: return .unavailable("Isn't Available")
        case .needsDownload(let bytes), .needsDownloadAndBuild(let bytes):
            return .download(bytes: bytes)
        case .needsBuild: return .build
        case .available, nil:
            if !isChosen { return .use }
            return isLoaded ? .done : .load
        }
    }

    /// The word on the button.
    var label: String {
        switch self {
        case .download(let bytes): "Download \(ByteCount.gigabytes(bytes))"
        case .build: "Build Model"
        case .use: "Use Model"
        case .load: "Load Model"
        case .done: "Done"
        case .unavailable(let reason): reason
        }
    }

    /// Whether the button may be pressed.
    var isEnabled: Bool {
        if case .unavailable = self { return false }
        return true
    }

    /// Whether pressing it puts the sheet away. A download does not: the footer turns into the
    /// transfer's own row, which is where it is paused and canceled, and sending somebody to
    /// another window to stop what they just started is the worse answer.
    var dismisses: Bool {
        switch self {
        case .download, .build, .unavailable: false
        case .use, .load, .done: true
        }
    }
}
