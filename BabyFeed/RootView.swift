import SwiftUI

struct RootView: View {
    @Environment(AppRouter.self) private var router
    @AppStorage(BabyProfile.nameKey) private var babyName = ""
    /// Read so the whole tree re-renders when the time zone setting changes.
    @AppStorage(AppSettings.timeZoneKey) private var timeZoneIdentifier = ""
    @AppStorage(AppSettings.hasSeenSharingIntroKey) private var hasSeenSharingIntro = false
    @State private var wantsSharingSetup = false

    var body: some View {
        @Bindable var router = router

        TabView(selection: $router.tab) {
            Tab("Today", systemImage: "clock.fill", value: AppRouter.Tab.today) {
                HomeView()
            }
            Tab("History", systemImage: "calendar", value: AppRouter.Tab.history) {
                HistoryView()
            }
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
        // One sheet modifier, so an invite that arrives while the log sheet is
        // open replaces it instead of being dropped. Presented here rather than
        // inside Settings so an invite opened from Messages or the Camera works
        // from whatever tab happened to be showing.
        .sheet(item: $router.sheet) { sheet in
            switch sheet {
            case .log(let kind):
                LogFeedSheet(mode: .new(kind))
            case .pairing(let invitation):
                PairServerView(invitation: invitation)
            case .sharingIntro:
                SharingIntroView(wantsToSetUpSharing: $wantsSharingSetup)
            }
        }
        // Once, on the very first launch. Skipped entirely if something more
        // urgent already claimed the sheet — an invite tapped from Messages
        // right after installing shouldn't queue behind an explainer.
        .task {
            guard !hasSeenSharingIntro else { return }
            hasSeenSharingIntro = true
            guard router.sheet == nil, !SyncCredentials.isPaired else { return }
            router.sheet = .sharingIntro
        }
        .onChange(of: wantsSharingSetup) { _, wants in
            guard wants else { return }
            wantsSharingSetup = false
            router.sheet = .pairing(nil)
        }
    }
}

#Preview {
    RootView()
        .environment(AppRouter())
        .modelContainer(for: [FeedEntry.self, WeightEntry.self, Baby.self], inMemory: true)
}
