import SwiftData
import SwiftUI

struct RootView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppRouter.self) private var router
    @Environment(ToastCenter.self) private var toasts
    @AppStorage(BabyProfile.nameKey) private var babyName = ""
    /// Read so the whole tree re-renders when the time zone setting changes.
    @AppStorage(AppSettings.timeZoneKey) private var timeZoneIdentifier = ""
    @AppStorage(AppSettings.hasSeenOnboardingKey) private var hasSeenOnboarding = false
    @AppStorage(AppSettings.currentBabyIDKey) private var currentBabyIDRaw = ""
    @Query private var medications: [Medication]
    @Query(sort: \MedicationDose.time, order: .reverse) private var doses: [MedicationDose]
    @AppStorage(AppSettings.darkAtNightKey) private var darkAtNight = true
    @AppStorage(AppSettings.nightStartKey) private var nightStart = NightHours.standard.startMinutes
    @AppStorage(AppSettings.nightEndKey) private var nightEnd = NightHours.standard.endMinutes
    @Environment(\.scenePhase) private var scenePhase
    /// Whether it's night right now, by the "Dark at night" hours. Moved at
    /// each boundary and whenever the app comes to the front.
    @State private var isNight = false

    var body: some View {
        @Bindable var router = router

        TabView(selection: $router.tab) {
            Tab("Today", systemImage: "clock.fill", value: AppRouter.Tab.today) {
                HomeView()
            }
            Tab("Timeline", systemImage: "calendar.day.timeline.left", value: AppRouter.Tab.timeline) {
                CareTimelineView()
            }
            Tab("Health", systemImage: "stethoscope", value: AppRouter.Tab.health) {
                HealthView()
            }
            .badge(medicinesDue)
            Tab(babyName.isEmpty ? "Baby" : babyName, systemImage: "figure.child", value: AppRouter.Tab.baby) {
                BabyView()
            }
            Tab("Settings", systemImage: "gearshape.fill", value: AppRouter.Tab.settings) {
                SettingsView()
            }
        }
        // iOS 26: a persistent strip above the tab bar. Here: last fed / next due, tap to log.
        .tabViewBottomAccessory {
            NextFeedBar()
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        // Publish the chosen time zone once, here, so both SwiftUI's own date
        // rendering and every view that reads \.calendar agree on what "today"
        // means. Empty identifier = follow the device, which is the default.
        .environment(\.calendar, AppSettings.calendar)
        .environment(\.timeZone, AppSettings.timeZone)
        // Dark at night, whatever the phone's own setting, so a light-mode
        // phone doesn't flash white at the 3 a.m. feed. Outside those hours
        // the system decides.
        .preferredColorScheme(darkAtNight && isNight ? .dark : nil)
        .task(id: "\(darkAtNight)-\(nightStart)-\(nightEnd)") { await followNightHours() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { updateNight() }
        }
        // One sheet modifier, so an invite that arrives while the log sheet is
        // open replaces it instead of being dropped. Presented here rather than
        // inside Settings so an invite opened from Messages or the Camera works
        // from whatever tab happened to be showing.
        .sheet(item: $router.sheet) { sheet in
            switch sheet {
            case .log(let kind):
                LogFeedSheet(mode: .new(kind))
            case .logDiaper(let kind):
                LogDiaperSheet(mode: .new(kind))
            case .quickLog:
                QuickLogSheet()
            case .fineDays:
                FineDaysSheet(babyID: AppSettings.currentBabyID)
            case .join(let invitation):
                JoinView(invitation: invitation)
            case .pairing(let code):
                PairServerView(code: code)
            case .onboarding:
                OnboardingView()
            case .share(let babyID):
                ShareBabySheet(babyID: babyID)
            case .recoverySetup:
                if let phrase = SyncEngine.shared.recoveryPhrase {
                    RecoveryKeySetupView(phrase: phrase, babyName: babyName.isEmpty ? "your baby" : babyName) {
                        router.sheet = nil
                    }
                }
            case .editEntry(let ref):
                EntryEditor(ref: ref)
            case .addEntry:
                AddEntrySheet()
            case .newEntry(let kind):
                NewEntrySheet(kind: kind)
            case .newUpdate(let id):
                if let concern = modelContext.model(for: id) as? HealthConcern {
                    LogCareNoteSheet(mode: .update(concern))
                }
            case .giveDose(let id):
                LogDoseSheet(mode: .new(id.flatMap { modelContext.model(for: $0) as? Medication }))
            case .newMedication(let vitaminD):
                MedicationSheet(mode: vitaminD
                                ? .new(name: "Vitamin D", kind: .supplement, schedule: .daily, unit: .drop)
                                : .blank)
            case .trackConcern(let id):
                if let note = modelContext.model(for: id) as? CareNote {
                    LogConcernSheet(mode: .new(kind: note.kind, fromNote: note))
                }
            }
        }
        // Above the tab bar and its accessory, over whichever tab is showing:
        // a diaper logged on Today and a feed saved from its sheet both land
        // here, and so does the haptic that says it worked.
        .overlay(alignment: .bottom) {
            if let toast = toasts.current {
                LogToastView(toast: toast) { toasts.dismiss() }
                    // Alongside the buttons, not instead of them: a finger
                    // resting on the toast keeps it up.
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { _ in toasts.hold(true) }
                            .onEnded { _ in toasts.hold(false) }
                    )
                    .padding(.bottom, 150)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .id(toast.id)
            } else if let shield = toasts.shielding {
                // Invisible, the same size and place as the toast that just
                // left, swallowing a late tap on Undo rather than letting it
                // log whatever sits underneath.
                LogToastView(toast: shield) {}
                    .opacity(0)
                    .overlay {
                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture {}
                    }
                    .padding(.bottom, 150)
                    .accessibilityHidden(true)
            }
        }
        .sensoryFeedback(.success, trigger: toasts.current?.id) { _, new in new != nil }
        // Once, on the very first launch, and only on a phone with nothing on
        // it yet. Skipped entirely if something more urgent already claimed
        // the sheet: an invite tapped from Messages right after installing
        // shouldn't queue behind a welcome.
        .task {
            guard !hasSeenOnboarding else { return }
            hasSeenOnboarding = true
            guard router.sheet == nil, !SyncCredentials.isPaired,
                  BabyStore.realBabies(in: modelContext).isEmpty else { return }
            router.sheet = .onboarding
        }
    }
}

extension RootView {
    /// Medicines due now, for the Health tab's badge.
    private var medicinesDue: Int {
        let babyID = UUID(uuidString: currentBabyIDRaw)
        let babyDoses = doses.active(for: babyID)
        return medications.active(for: babyID).filter {
            MedicationStats.isDue($0, doses: babyDoses, now: .now, calendar: AppSettings.calendar)
        }.count
    }

    private var hours: NightHours { NightHours(startMinutes: nightStart, endMinutes: nightEnd) }

    private func updateNight() {
        isNight = hours.contains(.now, calendar: AppSettings.calendar)
    }

    /// Sleeps until the next boundary, then flips, for as long as the app
    /// runs. No polling in between.
    private func followNightHours() async {
        updateNight()
        while !Task.isCancelled {
            guard let next = hours.nextBoundary(after: .now, calendar: AppSettings.calendar) else { return }
            try? await Task.sleep(for: .seconds(max(1, next.timeIntervalSinceNow + 1)))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.6)) { updateNight() }
        }
    }
}

#Preview {
    RootView()
        .environment(AppRouter())
        .environment(ToastCenter())
        .modelContainer(.preview)
}
