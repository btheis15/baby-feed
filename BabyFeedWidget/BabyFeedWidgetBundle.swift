import SwiftUI
import WidgetKit

@main
struct BabyFeedWidgetBundle: WidgetBundle {
    var body: some Widget {
        LastFeedWidget()
        NextFeedLiveActivity()
    }
}
