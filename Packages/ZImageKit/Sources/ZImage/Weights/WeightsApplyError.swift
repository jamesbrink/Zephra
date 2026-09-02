// ZEPHRA-PATCH: new. Loading a model used to log an apply failure and carry on, so a half
// loaded model reported success and generated noise. These are what the apply throws instead.
import Foundation

/// Why installing a component's weights into its module tree failed.
public enum WeightsApplyError: Error, LocalizedError, Sendable {
  /// The weight file held nothing for this component.
  case noWeights(component: String)
  /// Nothing in the weight file matched a parameter the module actually has.
  case noMatchingWeights(component: String)
  /// `Module.update` rejected the parameters, usually a shape or structure mismatch.
  case applyFailed(component: String, reason: String)

  public var errorDescription: String? {
    switch self {
    case .noWeights(let component):
      return "No \(component) weights were found in the model files."
    case .noMatchingWeights(let component):
      return "None of the \(component) weights matched the model's parameters."
    case .applyFailed(let component, let reason):
      return "Could not load the \(component) weights: \(reason)"
    }
  }
}
