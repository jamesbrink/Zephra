/// The one definition of a megabyte and a gigabyte, so a limit typed in one place and read in
/// another means the same number of bytes.
///
/// Binary units throughout: the Performance tab's preference is stored in MiB, the
/// `ZEPHRA_*_MB` switches are read in MiB, and the two used to disagree by five percent.
public enum MemoryUnits {
    /// 2^20 bytes: the "MB" every preference and every environment switch counts in.
    public static let mebibyte = 1 << 20
    /// 2^30 bytes.
    public static let gibibyte = 1 << 30
}
