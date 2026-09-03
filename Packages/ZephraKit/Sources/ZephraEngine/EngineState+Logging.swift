extension EngineState {
    /// A short, stable name for the log. The associated values are left out on purpose: a state
    /// transition is one line, and progress payloads would turn the log into a firehose.
    var logName: String {
        switch self {
        case .idle: "idle"
        case .checkingModel: "checkingModel"
        case .downloading: "downloading"
        case .building: "building"
        case .loading: "loading"
        case .warmingUp: "warmingUp"
        case .ready: "ready"
        case .generating: "generating"
        case .upscaling: "upscaling"
        case .cancelling: "cancelling"
        case .failed(let error): "failed(\(error.message))"
        }
    }
}
