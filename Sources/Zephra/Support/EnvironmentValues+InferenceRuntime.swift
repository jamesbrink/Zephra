import SwiftUI
import ZephraCore

/// How the composition root hands the GPU runtime down to the Performance tab.
///
/// The concrete runtime is built in `ZephraApp` beside the backend factory, so no view has to
/// know which backend — or which GPU framework — is underneath. Nil means a build with no
/// runtime at all, which is what `ZEPHRA_PREVIEW_STATE` and SwiftUI previews get.
extension EnvironmentValues {
    @Entry var inferenceRuntime: (any InferenceRuntime)?
}
