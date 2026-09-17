import SwiftUI

struct RootView: View {
    @Environment(AppRouter.self) private var router
    @AppStorage(BabyProfile.nameKey) private var babyName = ""

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
        .sheet(isPresented: $router.showLogSheet) {
            LogFeedSheet(mode: .new(router.pendingLogKind ?? .formula))
        }
    }
}

#Preview {
    RootView()
        .environment(AppRouter())
        .modelContainer(for: [FeedEntry.self, WeightEntry.self], inMemory: true)
}
