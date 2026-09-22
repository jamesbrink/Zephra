import Foundation
import ZephraCore
import ZephraLinkProtocol

/// What the reference pictures are, as an offer and a receipt name them.
///
/// One place, because two surfaces ask: the destination picker offers on every settings change
/// and Generate submits. A `GenerationInput` is a picture without its pixels — a size, a length
/// and a digest the Mac checks the blob against — so the order here is the order the model
/// reads them in and the order the blobs go in.
extension GenerationDispatch {
    /// Each picture as the strict protocol names it, in the order the model reads them.
    ///
    /// `originHost` is the Mac the picture came out of, resolved from the library name the
    /// picture carries: a reference fetched off one Mac and submitted to another is a picture
    /// the destination has never seen, and the Mac it came from is what says whether it may be.
    func inputs(for pictures: [ReferencePicture]) -> [GenerationInput] {
        pictures.map { picture in
            GenerationInput(
                data: picture.data,
                originHost: picture.origin.flatMap { hosts.catalog.entry(named: $0)?.hostID },
                dimensions: picture.size)
        }
    }

    /// What names this set of pictures for a `task(id:)`, which is how the destination picker
    /// tells one strip from another without holding the bytes twice.
    func fingerprint(of pictures: [ReferencePicture]) -> String {
        pictures.isEmpty
            ? "none"
            : pictures.map { GenerationInput.digest($0.data) }.joined(separator: ",")
    }
}
