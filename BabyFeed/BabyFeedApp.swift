import SwiftData
import SwiftUI
import UserNotifications

/// One container for the app and its App Intents (Siri runs intents in-process).
enum AppModelContainer {
    static let shared: ModelContainer = {
        let schema = Schema([FeedEntry.self, WeightEntry.self, Baby.self])
        do {
            return try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema)])
        } catch {
            fatalError("Could not create the model container: \(error)")
        }
    }()
}

@main
struct BabyFeedApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @State private var router = AppRouter()

    init() {
        BabyStore.bootstrap(in: AppModelContainer.shared.mainContext)
        SyncEngine.shared.start(container: AppModelContainer.shared)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(router)
                .onOpenURL { url in
                    router.handle(url: url)
                }
                .onAppear {
                    appDelegate.router = router
                }
        }
        .modelContainer(AppModelContainer.shared)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                SyncEngine.shared.requestSync()
            }
        }
    }
}

/// Receives notification taps and actions ("Log a feed", "Snooze").
@MainActor
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    weak var router: AppRouter?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        ReminderScheduler.registerCategories()
        return true
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        switch response.actionIdentifier {
        case ReminderScheduler.snoozeAction:
            await ReminderScheduler.snooze()
        case ReminderScheduler.logAction, UNNotificationDefaultActionIdentifier:
            router?.openLog(kind: nil)
        default:
            break
        }
    }
}
