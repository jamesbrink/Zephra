import Foundation

extension WanVAEConfiguration {
    /// The real release's `vae/config.json`, copied number for number so a caller has the
    /// layout without reading the file; `VAEWeightKeyTests` checks the file still says this.
    ///
    /// Base 160 in and 256 out, stages at 1x, 2x, 4x and 4x with two blocks each, time halved
    /// under the second and third downsamplers, 48 latent channels from 12 patched colour
    /// channels: 16 pixels a latent cell, four frames a latent frame after the first.
    public static let wan22 = WanVAEConfiguration(
        baseDim: 160,
        decoderBaseDim: 256,
        dimMult: [1, 2, 4, 4],
        numResBlocks: 2,
        temporalDownsample: [false, true, true],
        zDim: 48,
        inChannels: 12,
        outChannels: 12,
        patchSize: 2,
        latentsMean: [
            -0.2289, -0.0052, -0.1323, -0.2339, -0.2799, 0.0174, 0.1838, 0.1557,
            -0.1382, 0.0542, 0.2813, 0.0891, 0.1570, -0.0098, 0.0375, -0.1825,
            -0.2246, -0.1207, -0.0698, 0.5109, 0.2665, -0.2108, -0.2158, 0.2502,
            -0.2055, -0.0322, 0.1109, 0.1567, -0.0729, 0.0899, -0.2799, -0.1230,
            -0.0313, -0.1649, 0.0117, 0.0723, -0.2839, -0.2083, -0.0520, 0.3748,
            0.0152, 0.1957, 0.1433, -0.2944, 0.3573, -0.0548, -0.1681, -0.0667,
        ],
        latentsStd: [
            0.4765, 1.0364, 0.4514, 1.1677, 0.5313, 0.4990, 0.4818, 0.5013,
            0.8158, 1.0344, 0.5894, 1.0901, 0.6885, 0.6165, 0.8454, 0.4978,
            0.5759, 0.3523, 0.7135, 0.6804, 0.5833, 1.4146, 0.8986, 0.5659,
            0.7069, 0.5338, 0.4889, 0.4917, 0.4069, 0.4999, 0.6866, 0.4093,
            0.5709, 0.6065, 0.6415, 0.4944, 0.5726, 1.2042, 0.5458, 1.6887,
            0.3971, 1.0600, 0.3943, 0.5537, 0.5444, 0.4089, 0.7468, 0.7744,
        ])
}
