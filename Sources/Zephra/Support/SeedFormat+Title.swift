import ZephraEngine

extension SeedFormat {
    /// How the setting reads in the General tab's picker.
    var title: String {
        switch self {
        case .hex: "Short hex"
        case .decimal: "Number"
        }
    }
}
