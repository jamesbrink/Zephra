/// Byte counts as people read them, so every gigabyte figure in the app is written one way.
public enum ByteCount {
    /// Bytes as gigabytes to one decimal place, with a whole number left whole: "13.3 GB", "7 GB".
    public static func gigabytes(_ bytes: Int64) -> String {
        let tenths = Int((Double(bytes) / 100_000_000).rounded())
        let whole = tenths / 10
        let remainder = tenths % 10
        return remainder == 0 ? "\(whole) GB" : "\(whole).\(remainder) GB"
    }
}
