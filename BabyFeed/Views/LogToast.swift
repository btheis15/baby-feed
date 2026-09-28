import Observation
import SwiftData
import SwiftUI

/// "Wet diaper · 2:14 PM  [Undo] [Edit]" — the proof a tap landed.
///
/// A diaper saves the instant it's tapped, with nothing to confirm, which is
/// right for the most frequent thing anyone logs; the price is that a stray
/// tap needs an easy way back. Five seconds of Undo is that way back, and it
/// beats an "are you sure?" on the hundred taps that were right.
@Observable
@MainActor
final class ToastCenter {
    struct Toast: Identifiable {
        let id = UUID()
        let title: String
        let systemImage: String
        let tint: Color
        var undo: (() -> Void)?
        var edit: (() -> Void)?
    }

    private(set) var current: Toast?
    private var dismissal: Task<Void, Never>?

    func show(_ toast: Toast, for seconds: Double = 5) {
        withAnimation(.snappy) { current = toast }
        dismissal?.cancel()
        dismissal = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.dismiss()
        }
    }

    func dismiss() {
        dismissal?.cancel()
        withAnimation(.snappy) { current = nil }
    }

    /// The toast after logging something new: "Wet diaper · 2:14 PM" with
    /// Undo, which takes it back out, and Edit, which opens it. Undo goes
    /// through the entry's own soft delete, so it reaches the other phone the
    /// same way the log did.
    func logged(_ item: TimelineItem, detail: String? = nil, context: ModelContext, router: AppRouter) {
        let entry = item.entry
        let ref = item.ref
        show(Toast(
            title: EntryRow.joined([item.shortTitle, detail, Self.when(item)]),
            systemImage: item.systemImage,
            tint: item.tint,
            undo: {
                entry.softDelete()
                // The same fan-out as logging it: the countdown, the widget
                // and sync all move back.
                FeedCoordinator.feedsDidChange(in: context)
            },
            edit: {
                router.sheet = .editEntry(ref)
            }
        ))
    }

    /// Deletes an entry from a swipe, with Undo. The Undo is what lets a swipe
    /// delete go through without an "are you sure?".
    func delete(_ item: TimelineItem, context: ModelContext) {
        let entry = item.entry
        withAnimation { entry.softDelete() }
        FeedCoordinator.feedsDidChange(in: context)
        show(Toast(
            title: "\(item.shortTitle) deleted",
            systemImage: "trash",
            tint: .red,
            undo: {
                withAnimation { entry.restore() }
                FeedCoordinator.feedsDidChange(in: context)
            }
        ))
    }

    /// When it happened, as the Timeline will show it: "2:14 PM", or
    /// "yesterday, 9:40 PM" for something backdated. A weigh-in has a day,
    /// not a time, so it only says when that day isn't today.
    private static func when(_ item: TimelineItem) -> String? {
        let zone = AppSettings.timeZone
        if case .weight(let weight) = item {
            guard !AppSettings.calendar.isDateInToday(weight.date) else { return nil }
            return weight.date.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted, timeZone: zone))
        }
        return ClockText.since(item.date, now: .now, in: zone)
    }
}

/// The floating card itself, pinned above the tab bar.
struct LogToastView: View {
    let toast: ToastCenter.Toast
    let onDismiss: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            // At the largest text sizes the buttons go under the title, which
            // would otherwise be squeezed down to "Wet diap…".
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 12) {
                        icon
                        title
                    }
                    HStack(spacing: 20) {
                        buttons
                    }
                }
            } else {
                HStack(spacing: 12) {
                    icon
                    title
                    Spacer(minLength: 8)
                    buttons
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
        .padding(.horizontal, 16)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(toast.title)
    }

    private var icon: some View {
        Image(systemName: toast.systemImage)
            .foregroundStyle(toast.tint)
            .font(.title3)
    }

    private var title: some View {
        Text(toast.title)
            .font(.subheadline.weight(.semibold))
            .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 2)
            .minimumScaleFactor(0.85)
    }

    @ViewBuilder
    private var buttons: some View {
        if let undo = toast.undo {
            Button("Undo") {
                undo()
                onDismiss()
            }
            .font(.subheadline.weight(.semibold))
        }
        if let edit = toast.edit {
            Button("Edit") {
                edit()
                onDismiss()
            }
            .font(.subheadline.weight(.semibold))
        }
    }
}
