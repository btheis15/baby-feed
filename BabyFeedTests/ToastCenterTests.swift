import SwiftUI
import Testing
@testable import BabyFeed

/// A toast that times out leaves an invisible shield behind for a moment, so
/// an Undo tap already on its way doesn't land on the diaper row underneath.
@MainActor
struct ToastCenterTests {
    private func toast() -> ToastCenter.Toast {
        ToastCenter.Toast(title: "Wet diaper · 2:14 PM", systemImage: "drop", tint: .blue, undo: {})
    }

    @Test func timingOutLeavesAShield() async throws {
        let center = ToastCenter()
        center.show(toast(), for: 0.05)
        try await Task.sleep(for: .seconds(0.3))
        #expect(center.current == nil)
        #expect(center.shielding != nil, "the late tap has somewhere harmless to land")
    }

    @Test func closingItByHandLeavesNoShield() {
        let center = ToastCenter()
        center.show(toast())
        center.dismiss()
        #expect(center.current == nil)
        #expect(center.shielding == nil)
    }

    @Test func holdingItKeepsItUp() async throws {
        let center = ToastCenter()
        center.show(toast(), for: 0.05)
        center.hold(true)
        try await Task.sleep(for: .seconds(0.3))
        #expect(center.current != nil)
        center.hold(false)
        #expect(center.current != nil, "letting go gives it a little longer, not an instant exit")
    }
}
