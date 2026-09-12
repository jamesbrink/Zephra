import SwiftUI
import ZephraCore

/// Whether seeds are shown as the short hex label or as the whole number.
///
/// Only the picker: nothing reads this key but the capsule and the inspectors that spell a
/// seed, which is Item 2's wiring. The example beside the names is the same seed both ways,
/// which says more than the names do.
struct SeedFormatRow: View {
    @AppStorage(MobileSettings.seedFormat) private var format = MobileSettings.initialSeedFormat

    /// One seed, shown both ways in the row's caption.
    private static let example: UInt64 = 0x7A3F_9C2E_1B0D_4F61

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker("Show seeds as", selection: $format) {
                ForEach(SeedFormat.allCases, id: \.self) { format in
                    Text(format.title).tag(format)
                }
            }
            .pickerStyle(.segmented)
            Text(Self.caption(Self.example))
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }

    /// One seed, spelled both ways: "7A3F·9C2E or 8813431244974720865. Files and the record
    /// always carry the number." The Mac's own control reads the same sentence.
    static func caption(_ seed: UInt64) -> String {
        "\(SeedFormat.hex.label(seed)) or \(SeedFormat.decimal.label(seed)). "
            + "Files and the record always carry the number."
    }
}

#Preview("Seed format") {
    Form { SeedFormatRow() }
}
