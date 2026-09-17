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

    @AppStorage(AppSettings.remindersEnabledKey) private var remindersEnabled = false
    @AppStorage(AppSettings.intervalMinutesKey) private var intervalMinutes = AppSettings.defaultIntervalMinutes
    @AppStorage(AppSettings.useAlarmKey) private var useAlarm = false
    @AppStorage(AppSettings.liveActivityKey) private var liveActivity = true
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
            .onChange(of: intervalMinutes) { _, _ in FeedCoordinator.settingsDidChange(in: modelContext) }
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
        switch SyncEngine.shared.status {
        case .notConfigured: "Not set up in this build"
        case .signedOut: "Sign in to share with other caregivers"
        case .syncing: "Syncing…"
        case .idle(let lastSync):
            if let lastSync { "Synced \(lastSync.formatted(date: .omitted, time: .shortened))" } else { "Signed in" }
        case .error: "Sync problem – tap for details"
        }
    }

    private var remindersSection: some View {
        Section {
            Toggle("Remind me for the next feed", isOn: $remindersEnabled)

            if remindersEnabled {
                Picker("Every", selection: $intervalMinutes) {
                    ForEach(AppSettings.intervalChoices, id: \.self) { minutes in
                        Text(intervalLabel(minutes)).tag(minutes)
                    }
                }

                if let suggested = suggestedInterval, suggested != intervalMinutes {
                    Button("Use typical for age (\(intervalLabel(suggested)))") {
                        intervalMinutes = suggested
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
            amountStepper("Formula", ml: $formulaML)
            amountStepper("Breast milk", ml: $breastMilkML)
        } header: {
            Text("Default amounts")
        } footer: {
            Text("Each feed you save becomes the next default, so you rarely need to change these by hand.")
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

    private var suggestedInterval: Int? {
        guard birthInterval > 0 else { return nil }
        let profile = BabyProfile(name: "", birthDate: Date(timeIntervalSince1970: birthInterval))
        let hours = FeedingGuidance.suggestedIntervalHours(ageDays: profile.ageInDays())
        let minutes = Int((hours * 60 / 30).rounded()) * 30
        return AppSettings.intervalChoices.min { abs($0 - minutes) < abs($1 - minutes) }
    }

    private func intervalLabel(_ minutes: Int) -> String {
        let hours = Double(minutes) / 60
        return "\(hours.formatted(.number.precision(.fractionLength(0...1)))) hours"
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
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
