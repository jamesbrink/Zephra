import Foundation

/// Choosing a size for a picture that already exists.
extension ModelCapabilities {
    /// The size to make a clip of `picture` at: the picture's own shape, at about `budget`
    /// pixels, on this model's grid.
    ///
    /// A clip is the picture moving, so its frame must be the picture's shape and not the
    /// offered preset nearest to it — a 4:3 photograph at a 3:2 preset is cropped or
    /// letterboxed before a frame is made. The budget is what decides the cost: the pixel
    /// count of the size in force, so a person who chose a small frame keeps a small frame
    /// when they hand a picture in. Each edge is then rounded to `sizeAlignment` and held
    /// inside `sizeBounds`, scaling the whole size first so the shape survives a bound on
    /// one edge, and only an extreme shape loses some of it to the other bound.
    ///
    /// A picture with an edge of zero has no shape and answers nil, as does a budget of none.
    public func size(matchingAspectOf picture: ImageSize, budget: Int) -> ImageSize? {
        guard picture.width > 0, picture.height > 0, budget > 0 else { return nil }
        let aspect = Double(picture.width) / Double(picture.height)
        var width = (Double(budget) * aspect).squareRoot()
        var height = width / aspect
        let grow = max(1, Double(sizeBounds.lowerBound) / min(width, height))
        width *= grow
        height *= grow
        let shrink = min(1, Double(sizeBounds.upperBound) / max(width, height))
        width *= shrink
        height *= shrink
        return fit(ImageSize(width: Int(width.rounded()), height: Int(height.rounded())))
    }
}
