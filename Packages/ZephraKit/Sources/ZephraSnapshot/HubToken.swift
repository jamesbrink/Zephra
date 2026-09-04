import Foundation

/// Where the hub client would find a Hugging Face token, if it found one.
///
/// Every model Zephra ships is public, so no download needs a token — but the hub client sends
/// whatever it finds, in the same places the `hf` tool looks, and a token that has expired or
/// been revoked turns every request into a refusal, public repository or not. That refusal is
/// then reported as "authentication required", which is exactly the wrong thing to tell
/// someone about a public model. So when a download is refused, this says which token was
/// sent and where it came from, and the message names it.
///
/// The order matches the client's: the environment first, then the files.
public nonisolated enum HubToken {
    /// A description of where a token was read from, for a message, or nil when there is none
    /// anywhere the client looks.
    public static func source(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> String? {
        for variable in ["HF_TOKEN", "HUGGING_FACE_HUB_TOKEN"] {
            if let token = environment[variable], !token.isEmpty {
                return "the \(variable) environment variable"
            }
        }
        var files: [URL] = []
        if let path = environment["HF_TOKEN_PATH"], !path.isEmpty {
            files.append(URL(filePath: NSString(string: path).expandingTildeInPath))
        }
        if let hfHome = environment["HF_HOME"], !hfHome.isEmpty {
            files.append(
                URL(filePath: NSString(string: hfHome).expandingTildeInPath).appending(path: "token"))
        }
        files.append(home.appending(path: ".cache/huggingface/token"))
        files.append(home.appending(path: ".huggingface/token"))
        return files.first(where: holdsToken).map { "the token file at \($0.path(percentEncoded: false))" }
    }

    /// What to tell someone whose download the hub refused: which token to remove or renew when
    /// one was sent, and that the model itself needs none. Without a token the refusal means
    /// the repository has gone behind a login since the catalog was written.
    public static func refusalMessage(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> String {
        if let source = source(environment: environment, home: home) {
            return "Hugging Face refused the token from \(source). Zephra's models are public "
                + "and need no token, so remove or renew it and try again."
        }
        return "Hugging Face now asks for a login to fetch this model, which Zephra does not "
            + "support. Check the repository's page."
    }

    private static func holdsToken(_ file: URL) -> Bool {
        guard let contents = try? String(contentsOf: file, encoding: .utf8) else { return false }
        return !contents.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
