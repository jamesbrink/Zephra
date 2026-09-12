/// What a picture's fetch is keyed on: the file it is for, and whether the Mac is in reach.
///
/// The Mac being in reach belongs in the key because a fetch that failed while it was away has
/// to be tried again when it comes back, and nothing else on these surfaces would say so: a
/// square that went grey mid-drop stayed grey until the view was built again, which for a cell
/// the person is looking at means until they scroll it off the screen and back.
///
/// `.task(id:)` cancels and re-runs on every change, so the fetch itself has to know when it
/// has nothing to do — which is why what arrived is kept as a `Fetched`, under the name it
/// arrived for. The key changing is not the same question as the picture changing.
struct FetchKey: Equatable {
    /// The file's name in the Mac's library.
    let name: String
    /// Whether the Mac can be asked for anything at all.
    let isLive: Bool
}
