import SwiftUI
import ZephraCore

/// Whether seeds are shown as the short hex label or as the whole number.
///
/// Only the picker: the choice reaches the window through `SeedFormatPreference`, which reads
/// the same key, so the chip and the inspectors change as the segment moves. The example
/// beside each name is the same seed both ways, which says more than the names do.
struct SeedFormatControl: View {
    @AppStorage(AppSettings.seedFormat) private var format = AppSettings.initialSeedFormat

    /// One seed, shown both ways in the picker's caption.
    private static let example: UInt64 = 0x7A3F_9C2E_1B0D_4F61

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker("Show seeds as", selection: $format) {
                ForEach(SeedFormat.allCases, id: \.self) { format in
                    Text(format.title).tag(format)
                }
            }
            .pickerStyle(.segmented)
            Text("\(SeedFormat.hex.label(Self.example)) or \(SeedFormat.decimal.label(Self.example)). Files and the record always carry the number.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }
}

#Preview("Seed format") {
    Form { Section("Generation") { SeedFormatControl() } }
        .formStyle(.grouped)
        .frame(width: 480)
}
