import SwiftData
import SwiftUI

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var entries: [FeedEntry]

    @AppStorage(FeedDefaults.volumeUnit) private var unitRaw = VolumeUnit.ounces.rawValue
    @AppStorage(AppSettings.weightUnitKey) private var weightUnitRaw = WeightUnit.poundsOunces.rawValue
    @AppStorage(AppSettings.timeZoneKey) private var timeZoneIdentifier = ""
    @AppStorage(FeedDefaults.amountKey(for: .formula)) private var formulaML: Double = 0
    @AppStorage(FeedDefaults.amountKey(for: .breastMilk)) private var breastMilkML: Double = 0
    /// Read so these rows update as the guidance follows the baby.
    @AppStorage(FeedDefaults.recommendedPerFeedKey) private var recommendedML: Double = 0
    @AppStorage(FeedDefaults.typicalKey(for: .formula)) private var formulaTypicalML: Double = 0
    @AppStorage(FeedDefaults.typicalKey(for: .breastMilk)) private var breastMilkTypicalML: Double = 0

    @AppStorage(AppSettings.remindersEnabledKey) private var remindersEnabled = false
    /// 0 means "typical for age".
    @AppStorage(AppSettings.intervalMinutesKey) private var intervalMinutesRaw = 0
    @AppStorage(AppSettings.useAlarmKey) private var useAlarm = false
    @AppStorage(AppSettings.liveActivityKey) private var liveActivity = true
    @AppStorage(BabyProfile.nameKey) private var babyName = ""
    @AppStorage(AppSettings.displayNameKey) private var displayName = ""
    @AppStorage(BabyProfile.birthDateKey) private var birthInterval: Double = 0
    @AppStorage(AppSettings.currentBabyIDKey) private var currentBabyIDRaw = ""

    @State private var permissionMessage: String?

    private var unit: VolumeUnit { VolumeUnit(rawValue: unitRaw) ?? .ounces }
    private var activeEntries: [FeedEntry] { entries.active(for: UUID(uuidString: currentBabyIDRaw)) }

    var body: some View {
        NavigationStack {
            Form {
                caregiversSection
                remindersSection
                unitsSection
                timeZoneSection
                defaultsSection
                siriSection
                exportSection
                aboutSection
            }
            .navigationTitle("Settings")
            .onChange(of: remindersEnabled) { _, enabled in
                if enabled {
                    Task {
                        let granted = await ReminderScheduler.requestAuthorization()
                        permissionMessage = granted ? nil : "Notifications are off for Baby Feed in iOS Settings, so reminders can't be shown."
                        FeedCoordinator.settingsDidChange(in: modelContext)
                    }
                } else {
                    FeedCoordinator.settingsDidChange(in: modelContext)
                }
            }
            .onChange(of: intervalMinutesRaw) { _, _ in FeedCoordinator.settingsDidChange(in: modelContext) }
            .onChange(of: useAlarm) { _, on in
                if on {
                    Task {
                        let granted = await FeedAlarmScheduler.requestAuthorization()
                        if !granted {
                            useAlarm = false
                            permissionMessage = "Alarm permission was not granted, so reminders will stay as notifications."
                        }
                        FeedCoordinator.settingsDidChange(in: modelContext)
                    }
                } else {
                    FeedCoordinator.settingsDidChange(in: modelContext)
                }
            }
            .onChange(of: liveActivity) { _, _ in FeedCoordinator.settingsDidChange(in: modelContext) }
            .onChange(of: unitRaw) { _, _ in FeedCoordinator.settingsDidChange(in: modelContext) }
        }
    }

    // MARK: Sections

    private var caregiversSection: some View {
        Section {
            NavigationLink {
                FamilyView()
            } label: {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Caregivers & sync")
                        Text(caregiversSubtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "person.2.fill")
                }
            }
        } footer: {
            Text("Share the log with your partner or anyone else who feeds the baby. Everyone sees the same feeds.")
        }
    }

    private var caregiversSubtitle: String {
        // Attribution is worthless if nobody's set a name, and the app never
        // asks outright – so say so here, where the setting lives.
        if displayName.isEmpty {
            return "Add your name so entries show who logged them"
        }
        switch SyncEngine.shared.status {
        case .localOnly: return "On this iPhone only · logging as \(displayName)"
        case .syncing: return "Syncing…"
        case .idle(let lastSync):
            if let lastSync {
                return "Synced \(lastSync.formatted(date: .omitted, time: .shortened))"
            }
            return "Logging as \(displayName)"
        case .error: return "Sync problem – tap for details"
        }
    }

    private var remindersSection: some View {
        Section {
            Toggle("Remind me for the next feed", isOn: $remindersEnabled)

            if remindersEnabled {
                // 0 is "typical for age", so the gap widens on its own as the
                // baby grows rather than staying where it was set in week one.
                Picker("Every", selection: $intervalMinutesRaw) {
                    Text("Typical for age · \(intervalLabel(AppSettings.suggestedIntervalMinutes))")
                        .tag(0)
                    ForEach(AppSettings.intervalChoices, id: \.self) { minutes in
                        Text(intervalLabel(minutes)).tag(minutes)
                    }
                }

                Toggle(isOn: $useAlarm) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Ring an alarm instead")
                        Text("Sounds even in silent mode or a Focus, like the Clock app.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Toggle(isOn: $liveActivity) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Countdown on Lock Screen")
                    Text("Live Activity in the Dynamic Island with time since the last feed.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let permissionMessage {
                Text(permissionMessage)
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
        } header: {
            Text("Reminders")
        } footer: {
            Text("The reminder is set automatically from the time of each feed you log. Newborns typically eat every 2–3 hours; pediatricians suggest waking a newborn who has gone about 4 hours without eating until birth weight is regained.")
        }
    }

    private var unitsSection: some View {
        Section("Units") {
            Picker("Volume", selection: $unitRaw) {
                ForEach(VolumeUnit.allCases) { unit in
                    Text(unit.title).tag(unit.rawValue)
                }
            }
            Picker("Weight", selection: $weightUnitRaw) {
                ForEach(WeightUnit.allCases) { unit in
                    Text(unit.title).tag(unit.rawValue)
                }
            }
        }
    }

    private var defaultsFooter: String {
        let name = babyName.isEmpty ? "Baby" : babyName
        if formulaTypicalML > 0 || breastMilkTypicalML > 0 {
            return "Bottles start at what you usually give, worked out from your recent feeds, so it moves as \(name) does. The recommendation for \(name)'s weight and age still shows when you log a feed. Pin an amount to stop both."
        }
        if recommendedML > 0 {
            return "Bottles start at the recommended amount for \(name)'s weight and age and follow it as they grow. Once you've logged a few, they'll start at what you usually give instead."
        }
        return "Bottles will start at the recommended amount once there's a weight and a birthday to work from. Until then they start at \(unit.format(milliliters: unit.toMilliliters(unit.defaultAmount)))."
    }

    private var timeZoneSection: some View {
        Section {
            NavigationLink {
                TimeZonePicker(identifier: $timeZoneIdentifier)
            } label: {
                LabeledContent("Time zone") {
                    Text(timeZoneIdentifier.isEmpty ? "Automatic" : TimeZonePicker.friendlyName(timeZoneIdentifier))
                }
            }
            if !timeZoneIdentifier.isEmpty {
                Button("Follow this iPhone again") { timeZoneIdentifier = "" }
            }
        } header: {
            Text("Time zone")
        } footer: {
            Text(timeZoneIdentifier.isEmpty
                 ? "Feed times follow this iPhone, so they adjust on their own when you travel."
                 : "Feed times stay on \(TimeZonePicker.friendlyName(timeZoneIdentifier)) wherever you are, so a night away doesn't get split across two days.")
        }
    }

    private var defaultsSection: some View {
        Section {
            amountRow("Formula", kind: .formula, ml: $formulaML)
            amountRow("Breast milk", kind: .breastMilk, ml: $breastMilkML)
        } header: {
            Text("Default amounts")
        } footer: {
            Text(defaultsFooter)
        }
    }

    private var siriSection: some View {
        Section {
            Label("“Log a feed in Baby Feed”", systemImage: "mic.fill")
            Label("“When did the baby last eat in Baby Feed?”", systemImage: "mic.fill")
            Label("Add the Last Feed widget to your Lock Screen or Home Screen", systemImage: "square.grid.2x2")
        } header: {
            Text("Siri, Shortcuts & widgets")
        } footer: {
            Text("Siri and the Shortcuts app can log feeds hands-free. The widget shows time since the last feed and opens the log with one tap.")
        }
    }

    private var exportSection: some View {
        Section {
            ShareLink(item: FeedStats.csv(activeEntries, unit: unit), subject: Text("Baby Feed log")) {
                Label("Export as CSV", systemImage: "square.and.arrow.up")
            }
            .disabled(activeEntries.isEmpty)
        } header: {
            Text("Export")
        } footer: {
            Text(activeEntries.isEmpty
                 ? "Log a feed first, then you can export your history."
                 : "\(activeEntries.count) feeds. The History tab also has a plain-text summary for the pediatrician.")
        }
    }

    private var aboutSection: some View {
        Section("About") {
            LabeledContent("Version", value: appVersion)
            Text("Feeds are stored on this device and, only if you share with other caregivers, in your own private sync backend. No ads, no tracking.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Helpers


    private func intervalLabel(_ minutes: Int) -> String {
        let hours = Double(minutes) / 60
        return "\(hours.formatted(.number.precision(.fractionLength(0...1)))) hours"
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    /// Either "Recommended (2.3 oz)" with a way to pin, or a pinned amount with
    /// a way to go back to following the guidance.
    @ViewBuilder
    private func amountRow(_ title: String, kind: FeedKind, ml: Binding<Double>) -> some View {
        if ml.wrappedValue > 0 {
            amountStepper(title, ml: ml)
            Button("Use the recommendation for \(title.lowercased())") {
                ml.wrappedValue = 0
            }
            .font(.footnote)
        } else {
            let resolved = FeedDefaults.amount(for: kind, unit: unit)
            LabeledContent(title) {
                Text(sourceLabel(resolved))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Button("Pin an amount for \(title.lowercased()) instead") {
                // Seed from whatever is showing, so pinning never jumps.
                ml.wrappedValue = resolved.ml
            }
            .font(.footnote)
        }
    }

    /// "Your usual · 20 ml" vs "Recommended · 70 ml" – a learned default that
    /// doesn't say so just looks like a wrong recommendation.
    private func sourceLabel(_ resolved: (ml: Double, source: FeedDefaults.AmountSource)) -> String {
        let amount = unit.format(milliliters: resolved.ml)
        switch resolved.source {
        case .learned: return "Your usual · \(amount)"
        case .recommended: return "Recommended · \(amount)"
        case .fallback: return "Starting at \(amount)"
        case .pinned: return amount
        }
    }

    private func amountStepper(_ title: String, ml: Binding<Double>) -> some View {
        let currentML = ml.wrappedValue > 0 ? ml.wrappedValue : unit.toMilliliters(unit.defaultAmount)
        let current = unit.rounded(unit.fromMilliliters(currentML))

        return Stepper(
            onIncrement: {
                ml.wrappedValue = unit.toMilliliters(min(unit.maximum, current + unit.step))
            },
            onDecrement: {
                ml.wrappedValue = unit.toMilliliters(max(unit.step, current - unit.step))
            }
        ) {
            HStack {
                Text(title)
                Spacer()
                Text(unit.format(milliliters: currentML))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }
}

#Preview {
    SettingsView()
        .environment(AppRouter())
        .modelContainer(for: [FeedEntry.self, WeightEntry.self, Baby.self], inMemory: true)
}
