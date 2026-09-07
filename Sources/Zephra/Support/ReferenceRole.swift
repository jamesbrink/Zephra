import ZephraCore

/// What a reference picture means to the model reading it, and every string that follows from
/// the difference.
///
/// Three models, three answers to "what is this picture for": LTX-2.5 holds it as a clip's
/// first frame, Z-Image and Qwen-Image start a noised copy of it, and FLUX.2 klein reads it as
/// extra tokens rather than starting from it at all — see "Starting from a picture" in
/// AGENTS.md. Nothing else in the interface should spell any of these strings out; a fourth
/// model with a fourth role adds a case here and every call site follows.
enum ReferenceRole: Hashable {
    /// The picture is the clip's first frame (LTX-2.5).
    case firstFrame
    /// The picture is a noised copy the schedule starts from (Z-Image, Qwen-Image).
    case startFrom
    /// The picture is read as tokens the model attends to, never started from (FLUX.2 klein).
    case reference

    /// The role a model's capabilities imply. `producesVideo` is checked first: LTX-2.5 also
    /// declares a non-degenerate `referenceStrengthBounds`, but holding a clip's first frame is
    /// what the picture is for there, not a share of the schedule to keep.
    init(capabilities: ModelCapabilities) {
        if capabilities.producesVideo {
            self = .firstFrame
        } else if capabilities.adjustsReferenceStrength {
            self = .startFrom
        } else {
            self = .reference
        }
    }

    /// The well's caption under the glyph, sentence case since it is a caption.
    var wellCaption: String {
        switch self {
        case .firstFrame: "First frame"
        case .startFrom: "Start from"
        case .reference: "Reference"
        }
    }

    /// The empty well's help text: what choosing or dropping a picture here does.
    var emptyWellHelp: String {
        switch self {
        case .firstFrame: "Choose the clip's first frame, or drop one here"
        case .startFrom: "Choose a picture to start from, or drop one here"
        case .reference: "Choose a picture to edit, or drop one here"
        }
    }

    /// The filled well's accessibility label.
    var filledWellAccessibilityLabel: String {
        switch self {
        case .firstFrame: "First frame"
        case .startFrom: "Starting picture"
        case .reference: "Reference image"
        }
    }

    /// `ReferenceImagePicker`'s open-panel message.
    var openPanelMessage: String {
        switch self {
        case .firstFrame: "Choose the clip's first frame"
        case .startFrom: "Choose a picture to start from"
        case .reference: "Choose a picture to edit"
        }
    }

    /// The strength slider's help text.
    var strengthHelp: String {
        switch self {
        case .firstFrame: "How far the clip may drift from its first frame. 0 holds it exactly."
        case .startFrom: "How much of the picture to keep. Lower keeps more of it."
        case .reference: "The whole picture is read; there is no strength to set."
        }
    }

    /// The inspector's row label for where the picture came from.
    var inspectorRowLabel: String {
        switch self {
        case .firstFrame: "First frame"
        case .startFrom: "Started from"
        case .reference: "Edited from"
        }
    }
}
