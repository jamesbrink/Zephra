import Foundation
import MLX
import MLXNN

/// `txt_in`: the vision-language encoder's hidden states brought into the transformer's width.
///
/// `out_layer(gelu_tanh(in_layer(text_norm(x))))`, no biases. The norm is the zero-centred one,
/// which is the only place in the model that stores `scale - 1`.
///
/// The width is square — `context_in_dim` equals the model's own — so a transposed weight would
/// load without complaint. `QwenImage21TransformerConfiguration.validated()` is what says the
/// two are meant to be equal.
final class QwenImage21TextProjection: Module {
    @ModuleInfo(key: "text_norm") var norm: QwenImage21ZeroCenterRMSNorm
    @ModuleInfo(key: "in_layer") var input: Linear
    @ModuleInfo(key: "out_layer") var output: Linear

    init(contextDim: Int, hidden: Int, eps: Float) {
        _norm.wrappedValue = QwenImage21ZeroCenterRMSNorm(dimensions: contextDim, eps: eps)
        _input.wrappedValue = Linear(contextDim, hidden, bias: false)
        _output.wrappedValue = Linear(hidden, hidden, bias: false)
    }

    func callAsFunction(_ x: MLXArray) -> MLXArray {
        output(geluApproximate(input(norm(x))))
    }
}
