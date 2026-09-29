import SwiftUI

extension FeedCountdown {
    /// "3 hours, 10 minutes" until `due`, kept current by the system a minute
    /// at a time, for the widget and the Live Activity.
    ///
    /// Not `.reference`, which says a single unit ("in 3 hours") once it's an
    /// hour or more away, and not a minute-precision `.timer`, which spells its
    /// units out too and ran off the end of the Dynamic Island. Anchored 59
    /// seconds past the due time because the system counts whole minutes
    /// down, and `minutesLeft` rounds up: this way the widget and Today's
    /// hero show the same minute.
    static func timeLeftFormat(to due: Date) -> SystemFormatStyle.DateOffset {
        SystemFormatStyle.DateOffset(to: due.addingTimeInterval(59), allowedFields: [.hour, .minute],
                                     maxFieldCount: 2, sign: .never)
    }
}
