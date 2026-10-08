import SwiftData
import SwiftUI

/// Caregivers and sync: where the log is, who else is on it, how to hand it
/// to another phone, and the recovery phrase that brings it back.
struct FamilyView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppRouter.self) private var router
    @Query private var babies: [Baby]
    @AppStorage(AppSettings.currentBabyIDKey) private var currentBabyIDRaw = ""
    @AppStorage(AppSettings.displayNameKey) private var displayName = ""

    @State private var sync = SyncEngine.shared
    @State private var showUnpairConfirm = false
    @State private var isBackingUp = false
    @State private var backUpMessage: String?

    private var activeBabies: [Baby] { babies.filter { $0.deletedAt == nil } }
    private var currentBaby: Baby? { activeBabies.first { $0.uuid.uuidString == currentBabyIDRaw } }

    var body: some View {
        List {
            whereTheDataIsSection
            whoIsLoggingSection
            if activeBabies.count > 1 { babySwitcherSection }
            sharingSection
            if sync.isConfigured || sync.recoveryPhrase != nil { recoverySection }
            if sync.isConfigured { stopSection }
            advancedSection
        }
        .navigationTitle("Caregivers")
        .task {
            if let baby = currentBaby, baby.isShared {
                await sync.refreshMembers(babyID: baby.uuid)
            }
        }
        .refreshable { await sync.syncNow() }
    }

    // MARK: Sections

    private var whereTheDataIsSection: some View {
        Section {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(sync.isConfigured ? "On this iPhone, and your Mac mini" : "Everything is on this iPhone")
                        .font(.subheadline.weight(.medium))
                    SyncStatusLabel(status: sync.status)
                        .font(.footnote)
                }
            } icon: {
                Image(systemName: sync.isConfigured ? "house.fill" : "iphone")
                    .foregroundStyle(.green)
            }

            if sync.serverNeedsUpdateForHealth {
                Text("Your Mac mini needs an update to share health records (concerns, medicines, visits). They're kept on this iPhone until it's done.")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }

            if !sync.isConfigured, sync.hasServer {
                Button {
                    backUp()
                } label: {
                    if isBackingUp {
                        ProgressView()
                    } else {
                        Label("Back up to your Mac mini", systemImage: "arrow.up.to.line")
                    }
                }
                .disabled(isBackingUp)
                if let backUpMessage {
                    Text(backUpMessage).font(.footnote).foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Where your data is")
        } footer: {
            Text(sync.isConfigured
                 ? "The log lives in this app and works with no signal. A copy goes to the Mac mini at your house, so another caregiver's phone can see it. Nowhere else."
                 : "The log lives in this app, works with no signal, and isn't uploaded anywhere.")
        }
    }

    private var whoIsLoggingSection: some View {
        Section {
            TextField("Your name", text: $displayName)
                .textInputAutocapitalization(.words)
                .onSubmit {
                    Task { await sync.updateDisplayName(displayName) }
                }
        } header: {
            Text("Who's logging")
        } footer: {
            Text("Saved with each entry, so a shared log shows who did what.")
        }
    }

    private var babySwitcherSection: some View {
        Section {
            ForEach(activeBabies) { baby in
                Button {
                    BabyStore.setCurrent(baby, in: modelContext)
                } label: {
                    LabeledContent(baby.displayName) {
                        if baby.uuid.uuidString == currentBabyIDRaw {
                            Image(systemName: "checkmark")
                        }
                    }
                }
                .tint(.primary)
            }
        } header: {
            Text("Babies on this phone")
        }
    }

    @ViewBuilder
    private var sharingSection: some View {
        Section {
            if sync.isConfigured {
                ForEach(sync.members) { member in
                    LabeledContent {
                        Text(member.isOwner ? "Started the log" : "Caregiver")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } label: {
                        Text(member.displayName.isEmpty ? "Unnamed caregiver" : member.displayName)
                    }
                }
            }

            Button {
                if let baby = currentBaby { router.sheet = .share(baby.uuid) }
            } label: {
                Label("Share \(currentBaby?.displayName ?? "this")'s log", systemImage: "person.badge.plus")
            }
            .disabled(currentBaby == nil || !sync.hasServer)
        } header: {
            Text("Sharing")
        } footer: {
            Text(sync.hasServer
                 ? (SyncEngine.joinAddress != nil
                    ? "Shows a code the other iPhone scans with its Camera, from anywhere."
                    : "Shows a code the other iPhone scans with its Camera. It needs your Mac mini's address from outside the house, which the server tells this phone once BABYFEED_PUBLIC_URL is set.")
                 : "This build doesn't know a server to share through. Add one under Advanced.")
        }
    }

    private var recoverySection: some View {
        Section {
            NavigationLink {
                RecoveryKeyView(babyName: currentBaby?.displayName ?? "your baby")
            } label: {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Your recovery phrase")
                        Text(RecoveryPhraseReminder.confirmed
                             ? "Hidden until you ask."
                             : "Not written down yet")
                            .font(.footnote)
                            .foregroundStyle(RecoveryPhraseReminder.confirmed ? Color.secondary : Color.orange)
                    }
                } icon: {
                    Image(systemName: "key.fill")
                }
            }
        } header: {
            Text("If every phone is lost")
        } footer: {
            Text("Sharing is the everyday way onto another phone. The phrase is for when there's no phone left to scan from.")
        }
    }

    private var stopSection: some View {
        Section {
            Button("Stop syncing this phone", role: .destructive) { showUnpairConfirm = true }
        } footer: {
            Text("The log stays on this iPhone. It just stops going to the Mac mini, and stops receiving what the other caregiver logs.")
        }
        .confirmationDialog("Stop syncing this phone?", isPresented: $showUnpairConfirm, titleVisibility: .visible) {
            Button("Stop syncing", role: .destructive) {
                Task { await sync.unpair(context: modelContext) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Nothing on this phone is deleted.")
        }
    }

    private var advancedSection: some View {
        Section {
            Button {
                router.sheet = .pairing(code: nil)
            } label: {
                Label("Connect by hand", systemImage: "keyboard")
            }
            .tint(.primary)
        } header: {
            Text("Advanced")
        } footer: {
            Text("Type a server address with an invite code or a recovery phrase. Only needed if the QR or a link won't do.")
        }
    }

    private func backUp() {
        isBackingUp = true
        backUpMessage = nil
        Task {
            do {
                try await sync.ensureConnected(.backUp)
                if !RecoveryPhraseReminder.confirmed, sync.recoveryPhrase != nil {
                    router.sheet = .recoverySetup
                }
            } catch SyncError.away {
                backUpMessage = SyncEngine.syncsAwayFromHome
                    ? "Can't reach your Mac mini right now. It'll back up by itself once it can."
                    : "Can't reach your Mac mini from here. It'll back up by itself once this phone is on your home Wi‑Fi."
            } catch {
                backUpMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
            isBackingUp = false
        }
    }
}

/// "Backed up · synced 2 min ago", or where things stand.
struct SyncStatusLabel: View {
    let status: SyncEngine.Status

    var body: some View {
        switch status {
        case .localOnly:
            Text("Not backed up").foregroundStyle(.secondary)
        case .syncing:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Syncing…").foregroundStyle(.secondary)
            }
        case .idle(let date):
            if let date {
                Text("Backed up to your Mac mini · synced \(date, format: .relative(presentation: .named))")
                    .foregroundStyle(.secondary)
            } else {
                Text("Backed up to your Mac mini").foregroundStyle(.secondary)
            }
        case .away(let pending):
            Text(SyncPlan.awayText(pending: pending)).foregroundStyle(.secondary)
        case .needsUpdate:
            Text("Your Mac mini needs an update").foregroundStyle(.orange)
        case .error(let message):
            Text(message).foregroundStyle(.orange)
        }
    }
}

#Preview {
    NavigationStack {
        FamilyView()
    }
    .environment(AppRouter())
    .modelContainer(.preview)
}
