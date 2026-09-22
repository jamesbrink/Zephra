import Foundation
import MLX
import MLXNN

/// Every convolution in the autoencoder: a plain two-dimensional one, symmetrically padded.
///
/// The reference calls this `QwenImage21CausalConv3d` and it **subclasses `nn.Conv2d`**. Its
/// forward squeezes the frame axis away, pads explicitly with `F.pad(x, self._padding)` where
/// `_padding` is `(pad_w, pad_w, pad_h, pad_h)`, runs the convolution with `padding = (0, 0)`,
/// and puts the frame axis back. The pad it applies is therefore exactly the symmetric padding
/// the convolution was configured with and would have applied itself: there is no causal
/// temporal padding anywhere in this model, and `cache_x` raises rather than prepending
/// context. Every stored kernel is 4-D, `[out, in, kh, kw]`, which the header confirms.
///
/// So the port is `Conv2d` and nothing else, and the frame axis is dropped entirely rather
/// than carried as a size-one dimension. This type exists to say so at the point a reader
/// would otherwise go looking for Wan's feature cache, and so that the checkpoint's key lands
/// straight on the parameter -- `encoder.conv_in.weight`, not `encoder.conv_in.conv.weight`.
///
/// **Why every `time_conv` is dead.** `QwenImage21Resample` holds one in its `upsample3d` and
/// `downsample3d` modes, and the encoder's stages 1 to 3 and the decoder's stages 0 to 2 are
/// built in those modes, so the checkpoint carries twelve tensors for six of them. Both are
/// guarded on what the feature cache holds at that index, and a still image is one chunk: on
/// the way in the cache is `None` there, and the branch taken merely records the activation;
/// on the way out it is the sentinel `"Rep"`, and the branch taken merely replaces it. The
/// convolution itself is reached only from the *second* chunk onward, and a still image never
/// has one. This is exact rather than an approximation, which is why those six modules are
/// left out of the tree altogether and `QwenImage21VAEWeights` drops their tensors at load;
/// `WeightKeyCoverageTests` names all twelve keys rather than letting them go unclaimed.
final class QwenImage21CausalConv: Conv2d {}
