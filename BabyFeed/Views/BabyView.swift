import SwiftData
import SwiftUI

/// Baby profile, weight log with its numbers, and the age-based feeding guide.
struct BabyView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.calendar) private var calendar
    @Query(sort: \WeightEntry.date, order: .reverse) private var allWeights: [WeightEntry]
    @Query private var babies: [Baby]
    @AppStorage(AppSettings.currentBabyIDKey) private var currentBabyIDRaw = ""

    @AppStorage(BabyProfile.nameKey) private var babyName = ""
    @AppStorage(BabyProfile.birthDateKey) private var birthInterval: Double = 0
    @AppStorage(BabyProfile.sexKey) private var sexRaw = BabySex.unspecified.rawValue
    @AppStorage(BabyProfile.dueDateKey) private var dueInterval: Double = 0
    @AppStorage(AppSettings.weightUnitKey) private var weightUnitRaw = WeightUnit.poundsOunces.rawValue
    @AppStorage(FeedDefaults.volumeUnit) private var unitRaw = VolumeUnit.ounces.rawValue
    @AppStorage(AppSettings.feedingStyleKey) private var feedingStyleRaw = FeedingStyle.formula.rawValue
    @AppStorage(AppSettings.feedsPerDayKey) private var feedsPerDay = 0

    @State private var showAddWeight = false

    private var weightUnit: WeightUnit { WeightUnit(rawValue: weightUnitRaw) ?? .poundsOunces }
    private var unit: VolumeUnit { VolumeUnit(rawValue: unitRaw) ?? .ounces }
    private var feedingStyle: FeedingStyle { FeedingStyle(rawValue: feedingStyleRaw) ?? .formula }
    private var profile: BabyProfile {
        BabyProfile(
            name: babyName,
            birthDate: birthInterval > 0 ? Date(timeIntervalSince1970: birthInterval) : nil,
            sex: BabySex(rawValue: sexRaw) ?? .unspecified,
            dueDate: dueInterval > 0 ? Date(timeIntervalSince1970: dueInterval) : nil
        )
    }
    private var projection: GrowthProjection? {
        GrowthProjector.project(weights: weights, profile: profile, calendar: calendar)
    }
    private var drift: GrowthDrift? {
        GrowthProjector.drift(weights: weights, profile: profile)
    }

    private var dueDateBinding: Binding<Date> {
        Binding(
            get: { profile.dueDate ?? profile.birthDate ?? AppSettings.calendar.startOfDay(for: .now) },
            set: { dueInterval = $0.timeIntervalSince1970 }
        )
    }
    private var weights: [WeightEntry] { allWeights.active(for: UUID(uuidString: currentBabyIDRaw)) }
    private var activeBabies: [Baby] { babies.filter { $0.deletedAt == nil } }

    private var birthDateBinding: Binding<Date> {
        Binding(
            get: { profile.birthDate ?? AppSettings.calendar.startOfDay(for: .now) },
            set: { birthInterval = $0.timeIntervalSince1970 }
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                profileSection
                weightSection
                growthSection
                guidanceSection
                caregiversSection
            }
            .navigationTitle(profile.displayName)
            .toolbar {
                if activeBabies.count > 1 {
                    ToolbarItem(placement: .topBarLeading) {
                        Menu {
                            ForEach(activeBabies) { baby in
                                Button {
                                    BabyStore.setCurrent(baby, in: modelContext)
                                } label: {
                                    if baby.uuid.uuidString == currentBabyIDRaw {
                                        Label(baby.displayName, systemImage: "checkmark")
                                    } else {
                                        Text(baby.displayName)
                                    }
                                }
                            }
                        } label: {
                            Label("Switch baby", systemImage: "arrow.left.arrow.right")
                        }
                    }
                }
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
            .onChange(of: birthInterval) { _, _ in
                BabyStore.profileDefaultsChanged(in: modelContext)
                FeedCoordinator.settingsDidChange(in: modelContext)
            }
            .onChange(of: babyName) { _, _ in
                BabyStore.profileDefaultsChanged(in: modelContext)
                FeedCoordinator.settingsDidChange(in: modelContext)
            }
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
                    birthInterval = AppSettings.calendar.startOfDay(for: .now).timeIntervalSince1970
                }
            } else {
                DatePicker("Birthday", selection: birthDateBinding, in: ...Date.now, displayedComponents: .date)
                if let age = profile.ageText(calendar: calendar) {
                    LabeledContent("Age", value: age)
                }
            }

            Picker("Sex", selection: $sexRaw) {
                ForEach(BabySex.allCases) { sex in
                    Text(sex.title).tag(sex.rawValue)
                }
            }

            if dueInterval > 0 {
                DatePicker("Due date", selection: dueDateBinding, displayedComponents: .date)
                if profile.isPreterm, let corrected = correctedAgeText {
                    LabeledContent("Corrected age", value: corrected)
                }
                Button("Born on time – remove due date") { dueInterval = 0 }
            } else if profile.birthDate != nil {
                Button("Born early? Add a due date") {
                    dueInterval = (profile.birthDate ?? .now).timeIntervalSince1970
                }
            }
        } header: {
            Text("Profile")
        } footer: {
            Text("The birthday drives the age-based feeding guide and the default reminder interval. Sex is only used for growth percentiles, which are measured separately for girls and boys. A due date lets a baby born early be compared at corrected age.")
        }
    }

    /// Corrected age in whole weeks and days, for a baby born early.
    private var correctedAgeText: String? {
        guard let days = profile.growthAgeDays(), days >= 0 else { return "not yet at due date" }
        let whole = Int(days)
        if whole < 14 { return whole == 1 ? "1 day" : "\(whole) days" }
        let weeks = whole / 7
        let extra = whole % 7
        return extra == 0 ? "\(weeks) weeks" : "\(weeks)w \(extra)d"
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
                    weightTrend
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

    /// The numbers the weight chart used to gesture at: the last step, the
    /// steadier whole-log rate, and the total since the first weigh-in.
    @ViewBuilder
    private var weightTrend: some View {
        if let change = WeightStats.lastChange(weights, calendar: calendar) {
            LabeledContent("Since last weigh-in") {
                VStack(alignment: .trailing, spacing: 1) {
                    Text(weightUnit.formatChange(grams: change.grams))
                        .monospacedDigit()
                        .foregroundStyle(change.grams >= 0 ? Color.green : Color.orange)
                    Text(change.days == 1 ? "over 1 day" : "over \(change.days) days")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }

        if let rate = WeightStats.overallGramsPerWeek(weights) {
            LabeledContent("Average gain") {
                VStack(alignment: .trailing, spacing: 1) {
                    Text(weightUnit.formatGain(gramsPerWeek: rate))
                        .monospacedDigit()
                    Text("typical 5–7 oz/week")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }

        if let total = WeightStats.changeSinceFirst(weights), let first = weights.last {
            LabeledContent("Since first weigh-in") {
                VStack(alignment: .trailing, spacing: 1) {
                    Text(weightUnit.formatChange(grams: total))
                        .monospacedDigit()
                    Text(first.date.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    /// Where the baby sits on the WHO curve, and what that implies for today.
    @ViewBuilder
    private var growthSection: some View {
        if let projection {
            Section {
                LabeledContent("Percentile") {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(GrowthProjector.ordinal(percentile: projection.anchorPercentile))
                            .monospacedDigit()
                        if let drift, abs(drift.deltaPercentile) >= 1 {
                            Text("was \(GrowthProjector.ordinal(percentile: drift.fromPercentile)) on \(drift.fromDate.formatted(date: .abbreviated, time: .omitted))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if !projection.isMeasured {
                    LabeledContent("Estimated today") {
                        VStack(alignment: .trailing, spacing: 1) {
                            Text(weightUnit.format(grams: projection.estimatedGrams))
                                .monospacedDigit()
                            Text("\(weightUnit.format(grams: projection.rangeGrams.lowerBound))–\(weightUnit.format(grams: projection.rangeGrams.upperBound))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if let days = GrowthProjector.daysUntilFreshWeight(projection) {
                    LabeledContent("Weigh-in due", value: days == 1 ? "in 1 day" : "in \(days) days")
                } else {
                    Label("Time for a fresh weight", systemImage: "scalemass")
                        .foregroundStyle(.orange)
                }

                if drift?.hasFallenAChannel == true {
                    Label(
                        "\(profile.displayName) has dropped a full percentile band since the last weigh-in. That's worth mentioning to your pediatrician – it's the thing they watch for.",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.footnote)
                    .foregroundStyle(.orange)
                }
            } header: {
                Text("Growth")
            } footer: {
                Text("WHO Child Growth Standards\(profile.isPreterm ? ", at corrected age" : ""). Babies tend to follow their own percentile, so the estimate carries the last weigh-in forward – it isn't a measurement. The percentile re-anchors whenever you log a real weight.")
            }
        } else if profile.sex == .unspecified, !weights.isEmpty, profile.birthDate != nil {
            Section {
                Picker("Sex", selection: $sexRaw) {
                    ForEach(BabySex.allCases) { sex in
                        Text(sex.title).tag(sex.rawValue)
                    }
                }
            } header: {
                Text("Growth")
            } footer: {
                Text("Set \(profile.displayName)'s sex to see percentiles and a daily target that keeps up as \(profile.displayName) grows. WHO's growth standards are measured separately for girls and boys, so there's no way to average them.")
            }
        }
    }

    private var guidanceSection: some View {
        let ageDays = profile.ageInDays(calendar: calendar)
        let band = ageDays.map(FeedingGuidance.ageBand(forAgeDays:))
        // Same projection the Today tab uses, so the two tabs can't disagree.
        let target = projection.flatMap {
            FeedingGuidance.dailyTarget(
                projection: $0,
                ageDays: ageDays,
                style: feedingStyle,
                feedsPerDay: feedsPerDay
            )
        } ?? FeedingGuidance.dailyTarget(
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

    private var caregiversSection: some View {
        Section {
            NavigationLink {
                FamilyView()
            } label: {
                Label("Caregivers & sync", systemImage: "person.2.fill")
            }
        } footer: {
            Text("Share \(profile.displayName)'s log with your partner or other caregivers so everyone sees the same feeds.")
        }
    }

    // MARK: Helpers

    private var weeklyGain: Double? { WeightStats.lastChange(weights, calendar: calendar)?.gramsPerWeek }

    private func deleteWeights(at offsets: IndexSet) {
        let visible = weights
        for index in offsets {
            visible[index].softDelete()
        }
        FeedCoordinator.settingsDidChange(in: modelContext)
    }
}

#Preview {
    BabyView()
        .environment(AppRouter())
        .modelContainer(for: [FeedEntry.self, WeightEntry.self, Baby.self], inMemory: true)
}
