import SwiftUI
import SwiftData

@main
struct BabyFeedApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(for: FeedEntry.self)
    }
}
