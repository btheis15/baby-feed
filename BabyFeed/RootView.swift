import SwiftUI

struct RootView: View {
    @Environment(AppRouter.self) private var router
    @AppStorage(BabyProfile.nameKey) private var babyName = ""
    /// Read so the whole tree re-renders when the time zone setting changes.
    @AppStorage(AppSettings.timeZoneKey) private var timeZoneIdentifier = ""

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
        .sheet(isPresented: $router.showLogSheet) {
            LogFeedSheet(mode: .new(router.pendingLogKind ?? .formula))
        }
    }
}

#Preview {
    RootView()
        .environment(AppRouter())
        .modelContainer(for: [FeedEntry.self, WeightEntry.self, Baby.self], inMemory: true)
}
