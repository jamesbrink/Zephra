import Flux2

/// The one knob this family owns: how large a tile its autoencoder decodes in.
public nonisolated enum Flux2Runtime {
    /// The latent tile edge, or nil for an exact, untiled decode. Read at the next decode.
    public static var vaeTileSize: Int? {
        get { Flux2Autoencoder.latentTile }
        set { Flux2Autoencoder.latentTile = newValue }
    }
}
