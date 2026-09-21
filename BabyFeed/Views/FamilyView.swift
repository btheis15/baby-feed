import SwiftData
import SwiftUI

/// Caregivers and sync. Says where the data is, who else can see it, and — now
/// that there's a server to pair with — how to let the other caregiver in.
struct FamilyView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var babies: [Baby]
    @AppStorage(AppSettings.currentBabyIDKey) private var currentBabyIDRaw = ""
    @AppStorage(AppSettings.displayNameKey) private var displayName = ""

    @State private var sync = SyncEngine.shared
    @State private var showPairing = false
    @State private var invite: SyncClient.Invite?
    @State private var inviteError: String?
    @State private var isCreatingInvite = false
    @State private var showUnpairConfirm = false

    private var activeBabies: [Baby] { babies.filter { $0.deletedAt == nil } }
    private var currentBaby: Baby? { activeBabies.first { $0.uuid.uuidString == currentBabyIDRaw } }

    var body: some View {
        List {
            whereTheDataIsSection
            whoIsLoggingSection
            if activeBabies.count > 1 { babySwitcherSection }
            sharingSection
        }
        .navigationTitle("Caregivers")
        .sheet(isPresented: $showPairing) {
            PairServerView()
        }
        .sheet(item: $invite) { invite in
            InviteView(invite: invite, babyName: currentBaby?.displayName ?? "the baby")
        }
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
                    Text(sync.isConfigured
                         ? "The log lives in this app and works with no signal. A copy goes to the server at your house so another caregiver's phone can see it — nowhere else."
                         : "The log lives in this app, works with no signal, and isn't uploaded anywhere.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: sync.isConfigured ? "house.fill" : "iphone")
                    .foregroundStyle(.green)
            }

            if sync.isConfigured {
                LabeledContent("Status") { SyncStatusLabel(status: sync.status) }
            }
        } header: {
            Text("Where your data is")
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
            Text("Saved with each feed, so a shared log shows who did what.")
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
        if sync.isConfigured {
            Section {
                ForEach(sync.members) { member in
                    LabeledContent {
                        Text(member.isOwner ? "Owner" : "Caregiver")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } label: {
                        Text(member.displayName.isEmpty ? "Unnamed caregiver" : member.displayName)
                    }
                }

                Button {
                    createInvite()
                } label: {
                    if isCreatingInvite {
                        ProgressView()
                    } else {
                        Label("Invite another caregiver", systemImage: "person.badge.plus")
                    }
                }
                .disabled(isCreatingInvite || currentBaby == nil)

                if let inviteError {
                    Text(inviteError).font(.footnote).foregroundStyle(.red)
                }
            } header: {
                Text("Sharing \(currentBaby?.displayName ?? "this log")")
            } footer: {
                Text("An invite is one code, good for an hour, for one phone.")
            }

            Section {
                Button("Stop syncing this phone", role: .destructive) { showUnpairConfirm = true }
            } footer: {
                Text("The log stays on this iPhone. It just stops going to the server, and stops receiving what the other caregiver logs.")
            }
            .confirmationDialog("Stop syncing this phone?", isPresented: $showUnpairConfirm, titleVisibility: .visible) {
                Button("Stop syncing", role: .destructive) { sync.unpair(context: modelContext) }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Nothing on this phone is deleted.")
            }
        } else {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Share this log with another caregiver.")
                        .font(.subheadline)
                    Text("It syncs through a small server you run yourself, on your Mac mini at home — not an account with a company. Each phone keeps its own copy and carries on working offline.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)

                Button {
                    showPairing = true
                } label: {
                    Label("Set up sharing", systemImage: "link")
                }
            } header: {
                Text("Sharing")
            } footer: {
                Text("Until then, the pediatrician summary under History shares as plain text to anyone who needs it.")
            }
        }
    }

    private func createInvite() {
        guard let baby = currentBaby else { return }
        isCreatingInvite = true
        inviteError = nil
        Task {
            do {
                // A baby that's only ever been on this phone has to exist on
                // the server before anyone can be invited to it.
                if !baby.isShared {
                    sync.share([baby], in: modelContext)
                    await sync.syncNow()
                }
                invite = try await sync.createInvite(babyID: baby.uuid)
                await sync.refreshMembers(babyID: baby.uuid)
            } catch {
                inviteError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
            isCreatingInvite = false
        }
    }
}

/// "Synced 2 minutes ago", or what went wrong.
struct SyncStatusLabel: View {
    let status: SyncEngine.Status

    var body: some View {
        switch status {
        case .localOnly:
            Text("This iPhone only").foregroundStyle(.secondary)
        case .syncing:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Syncing…").foregroundStyle(.secondary)
            }
        case .idle(let date):
            if let date {
                Text("Synced \(date, format: .relative(presentation: .named))")
                    .foregroundStyle(.secondary)
            } else {
                Text("Waiting to sync").foregroundStyle(.secondary)
            }
        case .error(let message):
            Text(message)
                .font(.footnote)
                .foregroundStyle(.orange)
                .multilineTextAlignment(.trailing)
        }
    }
}

extension SyncClient.Invite: Identifiable {
    var id: String { code }
}

#Preview {
    NavigationStack {
        FamilyView()
    }
    .modelContainer(for: [FeedEntry.self, WeightEntry.self, Baby.self, CareNote.self], inMemory: true)
}
