import Charts
import SwiftData
import SwiftUI

/// Baby profile, weight log with chart, and the age-based feeding guide.
struct BabyView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \WeightEntry.date, order: .reverse) private var weights: [WeightEntry]

    @AppStorage(BabyProfile.nameKey) private var babyName = ""
    @AppStorage(BabyProfile.birthDateKey) private var birthInterval: Double = 0
    @AppStorage(AppSettings.weightUnitKey) private var weightUnitRaw = WeightUnit.poundsOunces.rawValue
    @AppStorage(FeedDefaults.volumeUnit) private var unitRaw = VolumeUnit.ounces.rawValue
    @AppStorage(AppSettings.feedingStyleKey) private var feedingStyleRaw = FeedingStyle.formula.rawValue
    @AppStorage(AppSettings.feedsPerDayKey) private var feedsPerDay = 0

    @State private var showAddWeight = false

    private var weightUnit: WeightUnit { WeightUnit(rawValue: weightUnitRaw) ?? .poundsOunces }
    private var unit: VolumeUnit { VolumeUnit(rawValue: unitRaw) ?? .ounces }
    private var feedingStyle: FeedingStyle { FeedingStyle(rawValue: feedingStyleRaw) ?? .formula }
    private var profile: BabyProfile {
        BabyProfile(name: babyName, birthDate: birthInterval > 0 ? Date(timeIntervalSince1970: birthInterval) : nil)
    }

    private var birthDateBinding: Binding<Date> {
        Binding(
            get: { profile.birthDate ?? Calendar.current.startOfDay(for: .now) },
            set: { birthInterval = $0.timeIntervalSince1970 }
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                profileSection
                weightSection
                guidanceSection
            }
            .navigationTitle(profile.displayName)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showAddWeight = true
                    } label: {
                        Label("Add weight", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showAddWeight) {
                AddWeightSheet(weightUnit: weightUnit)
            }
            .onChange(of: birthInterval) { _, _ in FeedCoordinator.settingsDidChange(in: modelContext) }
            .onChange(of: babyName) { _, _ in FeedCoordinator.settingsDidChange(in: modelContext) }
            .onChange(of: feedingStyleRaw) { _, _ in FeedCoordinator.settingsDidChange(in: modelContext) }
            .onChange(of: feedsPerDay) { _, _ in FeedCoordinator.settingsDidChange(in: modelContext) }
        }
    }

    // MARK: Sections

    private var profileSection: some View {
        Section {
            TextField("Baby's name", text: $babyName)
                .textInputAutocapitalization(.words)
            if profile.birthDate == nil {
                Button("Set birthday") {
                    birthInterval = Calendar.current.startOfDay(for: .now).timeIntervalSince1970
                }
            } else {
                DatePicker("Birthday", selection: birthDateBinding, in: ...Date.now, displayedComponents: .date)
                if let age = profile.ageText() {
                    LabeledContent("Age", value: age)
                }
            }
        } header: {
            Text("Profile")
        } footer: {
            Text("The birthday drives the age-based feeding guide and the default reminder interval.")
        }
    }

    private var weightSection: some View {
        Section {
            if let latest = weights.first {
                VStack(alignment: .leading, spacing: 6) {
                    Text(weightUnit.format(grams: latest.grams))
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                    HStack {
                        Text(latest.date.formatted(date: .abbreviated, time: .omitted))
                        if let gain = weeklyGain {
                            Text("·")
                            Text(weightUnit.formatGain(gramsPerWeek: gain))
                                .foregroundStyle(gain >= 0 ? Color.green : Color.orange)
                        }
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)

                if weights.count >= 2 {
                    weightChart
                        .frame(height: 180)
                        .padding(.vertical, 6)
                }

                ForEach(weights) { entry in
                    HStack {
                        Text(entry.date.formatted(date: .abbreviated, time: .omitted))
                        if !entry.note.isEmpty {
                            Text(entry.note)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        Text(weightUnit.format(grams: entry.grams))
                            .monospacedDigit()
                    }
                }
                .onDelete(perform: deleteWeights)
            } else {
                Button {
                    showAddWeight = true
                } label: {
                    Label("Add \(profile.displayName)'s weight", systemImage: "scalemass")
                }
            }
        } header: {
            Text("Weight")
        } footer: {
            Text("Newborns often lose up to 7–10% in the first days, regain birth weight by about two weeks, then gain roughly 5–7 oz (150–200 g) a week.")
        }
    }

    private var weightChart: some View {
        let points = weights.reversed()
        return Chart(points) { entry in
            LineMark(
                x: .value("Date", entry.date, unit: .day),
                y: .value("Weight", displayValue(grams: entry.grams))
            )
            .interpolationMethod(.catmullRom)
            PointMark(
                x: .value("Date", entry.date, unit: .day),
                y: .value("Weight", displayValue(grams: entry.grams))
            )
        }
        .chartYAxisLabel(weightUnit == .kilograms ? "kg" : "lb")
        .chartYScale(domain: .automatic(includesZero: false))
    }

    private var guidanceSection: some View {
        let ageDays = profile.ageInDays()
        let band = ageDays.map(FeedingGuidance.ageBand(forAgeDays:))
        let target = FeedingGuidance.dailyTarget(
            weightGrams: weights.first?.grams,
            ageDays: ageDays,
            style: feedingStyle,
            feedsPerDay: feedsPerDay
        )

        return Section {
            Picker("Fed mostly with", selection: $feedingStyleRaw) {
                ForEach(FeedingStyle.allCases) { style in
                    Text(style.title).tag(style.rawValue)
                }
            }

            Stepper(value: $feedsPerDay, in: 0...14) {
                LabeledContent("Feeds per day", value: feedsPerDay == 0 ? "Typical for age" : "\(feedsPerDay)")
            }

            if let target {
                VStack(alignment: .leading, spacing: 6) {
                    Text("About \(unit.format(milliliters: target.targetML)) a day")
                        .font(.headline)
                    Text("Roughly \(unit.format(milliliters: target.perFeedML)) per feed at \(target.feedsPerDay) feeds.")
                    Text(target.basis)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            if let band {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Typical at this age · \(band.title)")
                        .font(.headline)
                    LabeledContent("Per feed", value: "\(unit.formatValue(unit.fromMilliliters(band.perFeedML.lowerBound)))–\(unit.format(milliliters: band.perFeedML.upperBound))")
                    LabeledContent("Feeds a day", value: "\(band.feedsPerDay.lowerBound)–\(band.feedsPerDay.upperBound)")
                    LabeledContent("Between feeds", value: "\(band.hoursBetween.lowerBound.formatted())–\(band.hoursBetween.upperBound.formatted()) h")
                    Text(band.note)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            } else {
                Text("Set the birthday to see what's typical for \(profile.displayName)'s age.")
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("How much to feed")
        } footer: {
            Text("Guidance from the American Academy of Pediatrics and CDC (2½ oz per pound per day, up to about 32 oz; breastfed babies average 25 oz a day after the first month). It's a starting point, not a prescription. Feed on demand and follow your pediatrician.")
        }
    }

    // MARK: Helpers

    private var weeklyGain: Double? {
        guard weights.count >= 2 else { return nil }
        let latest = weights[0], previous = weights[1]
        let weeks = latest.date.timeIntervalSince(previous.date) / (7 * 24 * 3600)
        guard weeks > 0.2 else { return nil }
        return (latest.grams - previous.grams) / weeks
    }

    private func displayValue(grams: Double) -> Double {
        switch weightUnit {
        case .poundsOunces: grams / WeightUnit.gramsPerPound
        case .kilograms: grams / 1000
        }
    }

    private func deleteWeights(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(weights[index])
        }
        FeedCoordinator.settingsDidChange(in: modelContext)
    }
}

#Preview {
    BabyView()
        .modelContainer(for: [FeedEntry.self, WeightEntry.self], inMemory: true)
}
