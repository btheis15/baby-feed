import CoreImage.CIFilterBuiltins
import SwiftData
import SwiftUI
import UIKit

/// Tap Share, and a QR appears. The other phone points its Camera at it, taps
/// the banner, and Baby Feed opens and joins. Nothing to type on either phone.
///
/// Also a link to send and the code in two groups of three for reading out,
/// because at 3 a.m. whichever is easiest right then is the right one.
struct ShareBabySheet: View {
    let babyID: UUID

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    private enum Phase: Equatable {
        case preparing
        case ready(SyncClient.Invite, link: URL)
        case away
        case failed(String)

        var isReady: Bool {
            if case .ready = self { return true }
            return false
        }
    }

    @State private var phase: Phase = .preparing
    @State private var sync = SyncEngine.shared
    /// Who was already on the log when the sheet opened, so a newcomer can be
    /// called out as they arrive.
    @State private var initialMembers: Set<UUID>?

    /// An invite made earlier this session, reused while it has more than an
    /// hour left, so opening Share twice doesn't hand out two codes.
    @MainActor private static var cachedInvites: [UUID: SyncClient.Invite] = [:]

    private var baby: Baby? { BabyStore.baby(withID: babyID, in: modelContext) }
    private var babyName: String { baby?.displayName ?? "the baby" }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    switch phase {
                    case .preparing:
                        ProgressView("Getting a code…")
                            .frame(maxWidth: .infinity, minHeight: 320)
                    case .ready(let invite, let link):
                        ready(invite: invite, link: link)
                    case .away:
                        if SyncEngine.syncsAwayFromHome {
                            problem(
                                symbol: "wifi.exclamationmark",
                                title: "Can't reach your Mac mini",
                                detail: "Check this phone is online and try again. Everything logged here is saved, and syncs once it can."
                            )
                        } else {
                            problem(
                                symbol: "wifi.exclamationmark",
                                title: "Sharing needs your home Wi‑Fi",
                                detail: "Both phones need to be on the same Wi‑Fi as your Mac mini. Everything logged here is saved, and syncs once you're home."
                            )
                        }
                    case .failed(let message):
                        problem(symbol: "exclamationmark.triangle", title: "Couldn't get a code", detail: message)
                    }
                }
                .padding(.vertical)
            }
            .navigationTitle("Share \(babyName)'s log")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task { await prepare() }
        .task(id: phase.isReady) {
            guard phase.isReady else { return }
            // Every few seconds while the code is up, to say who has joined.
            while !Task.isCancelled {
                await sync.refreshMembers(babyID: babyID)
                if initialMembers == nil { initialMembers = Set(sync.members.map(\.userID)) }
                try? await Task.sleep(for: .seconds(3))
            }
        }
        // Kept on while the code is showing, so it's still there when the
        // other phone gets its Camera open.
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
    }

    // MARK: States

    private func ready(invite: SyncClient.Invite, link: URL) -> some View {
        VStack(spacing: 22) {
            if let image = QRCode.image(for: link) {
                Image(uiImage: image)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 260)
                    .padding(16)
                    .background(.white, in: .rect(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.quaternary))
                    .accessibilityLabel("QR code for joining \(babyName)'s log")
            }

            VStack(spacing: 6) {
                Text("On the other iPhone, open the Camera and point it here.")
                    .font(.headline)
                Text("They need Baby Feed installed first. It works from anywhere.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal)

            joinedList

            VStack(spacing: 4) {
                Text("Or read out this code")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text(Self.grouped(invite.code))
                    .font(.system(size: 34, weight: .semibold, design: .monospaced))
                    .textSelection(.enabled)
                    .accessibilityLabel(invite.code.map(String.init).joined(separator: " "))
                Text("Works for a day, on up to \(maxPhones) phones.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ShareLink(item: link, message: Text(SyncMerge.inviteMessage(babyName: babyName, link: link))) {
                Label("Send link", systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .padding(.horizontal)
        }
    }

    /// "✓ Annette joined", for everyone who arrived while this was open.
    @ViewBuilder
    private var joinedList: some View {
        let newcomers = sync.members.filter { member in
            initialMembers.map { !$0.contains(member.userID) } ?? false
        }
        if !newcomers.isEmpty {
            VStack(spacing: 6) {
                ForEach(newcomers) { member in
                    Label("\(member.displayName.isEmpty ? "A caregiver" : member.displayName) joined",
                          systemImage: "checkmark.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.green)
                }
            }
            .transition(.opacity)
        }
    }

    private func problem(symbol: String, title: String, detail: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(title)
                .font(.title3.bold())
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Try again") {
                Task { await prepare() }
            }
            .buttonStyle(.bordered)
            .padding(.top, 4)
        }
        .padding(.horizontal, 28)
        .frame(maxWidth: .infinity, minHeight: 320)
    }

    private var maxPhones: Int { 10 }

    // MARK: Getting the invite

    private func prepare() async {
        guard let baby else {
            phase = .failed("That baby isn't on this phone any more.")
            return
        }
        phase = .preparing
        do {
            let invite: SyncClient.Invite
            if let cached = Self.cachedInvites[babyID], cached.expiresAt.timeIntervalSinceNow > 3600,
               SyncCredentials.isPaired {
                invite = cached
            } else {
                invite = try await sync.invite(for: baby)
                Self.cachedInvites[babyID] = invite
            }
            guard let link = sync.link(for: invite, baby: baby) else {
                phase = .failed(SyncEngine.joinAddress == nil
                                ? "Sharing needs your Mac mini's address from outside the house. Set BABYFEED_PUBLIC_URL on the server, then open Baby Feed once on your home Wi‑Fi."
                                : "This iPhone doesn't have \(baby.displayName)'s key, so it can't share the log. Share it from the phone that added it.")
                return
            }
            phase = .ready(invite, link: link)
        } catch SyncError.away {
            phase = .away
        } catch {
            phase = .failed((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
    }

    /// "D8WAQK" → "D8W AQK", for reading out.
    static func grouped(_ code: String) -> String {
        let normalized = SyncMerge.normalizedInviteCode(code)
        guard normalized.count == SyncMerge.inviteCodeLength else { return normalized }
        let middle = normalized.index(normalized.startIndex, offsetBy: SyncMerge.inviteCodeLength / 2)
        return "\(normalized[..<middle]) \(normalized[middle...])"
    }
}

/// A QR for a link, sharp enough for a camera across a dim room.
enum QRCode {
    /// Rendered at the QR's native size and scaled up without smoothing — a
    /// blurred QR is one a camera won't read.
    static func image(for url: URL) -> UIImage? {
        guard let data = url.absoluteString.data(using: .utf8) else { return nil }
        let filter = CIFilter.qrCodeGenerator()
        filter.message = data
        // M: survives a fingerprint on the screen, still compact enough to read
        // across a room in bad light.
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 12, y: 12))
        let context = CIContext()
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

extension SyncClient.Invite: Identifiable, Equatable {
    var id: String { code }

    static func == (lhs: SyncClient.Invite, rhs: SyncClient.Invite) -> Bool {
        lhs.code == rhs.code && lhs.babyID == rhs.babyID && lhs.expiresAt == rhs.expiresAt
    }
}

#Preview {
    ShareBabySheet(babyID: UUID())
        .modelContainer(.preview)
}
