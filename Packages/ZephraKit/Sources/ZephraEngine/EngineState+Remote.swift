/// Why a paired device's request cannot be queued, said in one sentence.
///
/// The app target words the same states for the canvas, the window subtitle and the File menu
/// in `EngineState+Display`; it cannot be reached from here and a phone is not a canvas. Same
/// vocabulary, though — "Preparing" for a load, "Warming up", "Stopping" — so a device and the
/// Mac beside it never claim to be doing two different things.
extension EngineState {
    /// What to tell a device that asked for a generation while the engine was in this state.
    ///
    /// Only ever read when the state does not accept one, which is why `.ready` and a
    /// `.generating` that is draining have no interesting answer here.
    var remoteRefusal: String {
        switch self {
        case .idle: "No model is loaded yet."
        case .checkingModel: "Zephra is checking the model."
        case .downloading: "Zephra is downloading a model."
        case .building: "Zephra is building a model."
        case .loading: "Zephra is preparing a model."
        case .warmingUp: "Zephra is warming up."
        case .upscaling: "Zephra is upscaling a picture."
        case .cancelling: "Zephra is stopping."
        case .failed(let error): error.message
        case .ready, .generating: "Zephra cannot take new work just now."
        }
    }
}
