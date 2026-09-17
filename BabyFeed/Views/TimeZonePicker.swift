import SwiftUI

/// Searchable time zone list, with "Automatic" as the default at the top.
///
/// Feed times follow the phone unless a caregiver pins a zone here – useful
/// when travelling, so a night away doesn't get split across two days, and
/// when caregivers in different zones want one shared reading of "today".
struct TimeZonePicker: View {
    @Binding var identifier: String
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    /// "Chicago (CDT, −5)" – the city matters more than the region prefix.
    static func friendlyName(_ identifier: String) -> String {
        guard let zone = TimeZone(identifier: identifier) else { return identifier }
        let city = identifier
            .split(separator: "/")
            .last
            .map { $0.replacingOccurrences(of: "_", with: " ") } ?? identifier
        let abbreviation = zone.abbreviation() ?? ""
        let hours = Double(zone.secondsFromGMT()) / 3600
        let offset = hours == hours.rounded()
            ? String(format: "%+d", Int(hours))
            : String(format: "%+.1f", hours)
        return abbreviation.isEmpty ? "\(city) (GMT\(offset))" : "\(city) (\(abbreviation), GMT\(offset))"
    }

    /// Only zones with a region prefix, which excludes the legacy aliases and
    /// bare abbreviations that would otherwise clutter the list.
    private static let allIdentifiers: [String] = TimeZone.knownTimeZoneIdentifiers
        .filter { $0.contains("/") }
        .sorted()

    private var matches: [String] {
        let query = search.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return Self.allIdentifiers }
        return Self.allIdentifiers.filter {
            $0.replacingOccurrences(of: "_", with: " ").localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        List {
            Section {
                Button {
                    identifier = ""
                    dismiss()
                } label: {
                    LabeledContent {
                        if identifier.isEmpty {
                            Image(systemName: "checkmark")
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Automatic")
                            Text("Follow this iPhone · currently \(Self.friendlyName(TimeZone.current.identifier))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .tint(.primary)
            } footer: {
                Text("Automatic keeps up with the phone, so times adjust on their own when you travel.")
            }

            Section {
                ForEach(matches, id: \.self) { zone in
                    Button {
                        identifier = zone
                        dismiss()
                    } label: {
                        LabeledContent {
                            if identifier == zone {
                                Image(systemName: "checkmark")
                            }
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(Self.friendlyName(zone))
                                Text(zone)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .tint(.primary)
                }
            } header: {
                Text("Pin a time zone")
            }
        }
        .navigationTitle("Time zone")
        .searchable(text: $search, prompt: "Search cities")
    }
}

#Preview {
    NavigationStack {
        TimeZonePicker(identifier: .constant("America/Chicago"))
    }
}
