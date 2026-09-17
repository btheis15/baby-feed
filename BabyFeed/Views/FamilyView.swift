import SwiftData
import SwiftUI

/// Caregivers & sync: sign in, share the baby with a code, see who's on the
/// log, join someone else's baby, switch between babies.
struct FamilyView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppRouter.self) private var router
    @Query private var babies: [Baby]
    @AppStorage(AppSettings.currentBabyIDKey) private var currentBabyIDRaw = ""
    @AppStorage(AppSettings.displayNameKey) private var displayName = ""

    private let engine = SyncEngine.shared

    @State private var showSignIn = false
    @State private var inviteCode: String?
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var confirmLeave = false
    @State private var memberToRemove: MemberDTO?

    private var currentBaby: Baby? {
        babies.first { $0.uuid.uuidString == currentBabyIDRaw && $0.deletedAt == nil }
    }

    private var activeBabies: [Baby] { babies.filter { $0.deletedAt == nil } }

    private var isOwner: Bool {
        guard let baby = currentBaby else { return false }
        if let me = engine.members.first(where: { $0.userID == engine.userID }) { return me.isOwner }
        return baby.ownerUserID == engine.userID?.uuidString
    }

    var body: some View {
        List {
            switch engine.status {
            case .notConfigured:
                notConfiguredSection
            case .signedOut:
                signedOutSection
            default:
                accountSection
                babySection
                joinSection
                if activeBabies.count > 1 {
                    babiesSection
                }
                statusSection
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .font(.footnote)
                }
            }
        }
        .navigationTitle("Caregivers")
        .sheet(isPresented: $showSignIn) {
            SignInSheet()
        }
        .task(id: currentBabyIDRaw) {
            if let baby = currentBaby, baby.isShared {
                await engine.refreshMembers(for: baby.uuid)
            }
        }
        .confirmationDialog("Leave \(currentBaby?.displayName ?? "this baby")'s log?", isPresented: $confirmLeave, titleVisibility: .visible) {
            Button("Leave and remove from this phone", role: .destructive) { leave() }
        } message: {
            Text("The log stays with the other caregivers. You can rejoin later with a new code.")
        }
        .confirmationDialog("Remove \(memberToRemove?.displayName ?? "this caregiver")?", isPresented: Binding(get: { memberToRemove != nil }, set: { if !$0 { memberToRemove = nil } }), titleVisibility: .visible) {
            Button("Remove", role: .destructive) {
                if let member = memberToRemove { remove(member) }
            }
        }
    }

    // MARK: Sections

    private var notConfiguredSection: some View {
        Section {
            Label("Sync isn't set up in this build", systemImage: "icloud.slash")
            Text("Follow supabase/README.md in the project to create the free backend and add its URL and key to SupabaseConfig.swift. Until then, everything is saved on this phone only.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        } header: {
            Text("Sharing")
        }
    }

    private var signedOutSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Label("Share the log with other caregivers", systemImage: "person.2.fill")
                    .font(.headline)
                Text("Sign in, then share \(currentBaby?.displayName ?? "the baby") with your partner, grandparents or a nanny. Everyone sees the same feeds within seconds, and everything keeps working offline.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
            Button {
                showSignIn = true
            } label: {
                Label("Sign in to sync", systemImage: "person.crop.circle.badge.checkmark")
            }
        } header: {
            Text("Sharing")
        } footer: {
            Text("Feeds already on this phone are uploaded when you share, so nothing is lost.")
        }
    }

    private var accountSection: some View {
        Section {
            if let email = engine.userEmail {
                LabeledContent("Signed in as", value: email)
            }
            TextField("Your name (shown on feeds you log)", text: $displayName)
                .textInputAutocapitalization(.words)
                .onSubmit { saveDisplayName() }
            Button("Sign out", role: .destructive) {
                Task { await engine.signOut() }
            }
        } header: {
            Text("Account")
        }
    }

    @ViewBuilder
    private var babySection: some View {
        if let baby = currentBaby {
            Section {
                if baby.isShared {
                    if let inviteCode {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Invite code")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(inviteCode)
                                .font(.system(size: 34, weight: .bold, design: .monospaced))
                                .textSelection(.enabled)
                            Text("Valid for 7 days. The other person signs in and enters it under Caregivers → Join.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                        ShareLink(item: SyncMerge.inviteMessage(babyName: baby.displayName, code: inviteCode)) {
                            Label("Send invite", systemImage: "square.and.arrow.up")
                        }
                    }
                    Button {
                        newInvite(for: baby)
                    } label: {
                        Label(inviteCode == nil ? "Invite a caregiver" : "New code", systemImage: "person.badge.plus")
                    }
                    .disabled(isWorking)

                    ForEach(engine.members) { member in
                        HStack {
                            Image(systemName: member.isOwner ? "crown.fill" : "person.fill")
                                .foregroundStyle(member.isOwner ? .orange : .secondary)
                            Text(member.displayName.isEmpty ? "Caregiver" : member.displayName)
                            if member.userID == engine.userID {
                                Text("(you)").foregroundStyle(.secondary)
                            }
                            Spacer()
                            if isOwner, member.userID != engine.userID {
                                Button("Remove", role: .destructive) { memberToRemove = member }
                                    .buttonStyle(.borderless)
                            }
                        }
                    }

                    if !isOwner {
                        Button("Leave this log", role: .destructive) { confirmLeave = true }
                    }
                } else {
                    Button {
                        share(baby)
                    } label: {
                        if isWorking {
                            ProgressView()
                        } else {
                            Label("Share \(baby.displayName) with other caregivers", systemImage: "person.2.badge.plus")
                        }
                    }
                    .disabled(isWorking)
                }
            } header: {
                Text(baby.displayName)
            } footer: {
                Text(baby.isShared
                     ? "Everyone on this list sees and can log feeds. Any number of caregivers can join."
                     : "Uploads \(baby.displayName)'s log and gives you a code to hand to other caregivers.")
            }
        }
    }

    private var joinSection: some View {
        Section {
            Button {
                router.openJoin(code: nil)
            } label: {
                Label("Join another baby with a code", systemImage: "qrcode.viewfinder")
            }
        } footer: {
            Text("If someone else set up the baby, enter their code here. You can follow more than one baby.")
        }
    }

    private var babiesSection: some View {
        Section("Babies on this phone") {
            ForEach(activeBabies) { baby in
                Button {
                    BabyStore.setCurrent(baby, in: modelContext)
                    inviteCode = nil
                } label: {
                    HStack {
                        Text(baby.displayName)
                        if baby.isShared {
                            Image(systemName: "person.2.fill").foregroundStyle(.secondary).imageScale(.small)
                        }
                        Spacer()
                        if baby.uuid.uuidString == currentBabyIDRaw {
                            Image(systemName: "checkmark").foregroundStyle(.tint)
                        }
                    }
                }
                .foregroundStyle(.primary)
            }
        }
    }

    private var statusSection: some View {
        Section {
            HStack {
                Text("Status")
                Spacer()
                statusText
                    .foregroundStyle(.secondary)
            }
            Button("Sync now") {
                Task { await engine.syncNow() }
            }
        }
    }

    private var statusText: some View {
        Group {
            switch engine.status {
            case .syncing:
                Text("Syncing…")
            case .idle(let lastSync):
                if let lastSync {
                    Text("Synced \(lastSync, style: .relative) ago")
                } else {
                    Text("Ready")
                }
            case .error(let message):
                Text("Problem: \(message)")
                    .lineLimit(2)
            default:
                Text("—")
            }
        }
        .font(.subheadline)
    }

    // MARK: Actions

    private func share(_ baby: Baby) {
        isWorking = true
        errorMessage = nil
        Task {
            do {
                inviteCode = try await engine.share(baby, in: modelContext)
            } catch {
                errorMessage = error.localizedDescription
            }
            isWorking = false
        }
    }

    private func newInvite(for baby: Baby) {
        isWorking = true
        errorMessage = nil
        Task {
            do {
                inviteCode = try await engine.createInvite(for: baby)
            } catch {
                errorMessage = error.localizedDescription
            }
            isWorking = false
        }
    }

    private func saveDisplayName() {
        guard let baby = currentBaby, baby.isShared else { return }
        Task { try? await engine.updateOwnDisplayName(babyID: baby.uuid) }
    }

    private func remove(_ member: MemberDTO) {
        Task {
            do { try await engine.removeMember(member) } catch { errorMessage = error.localizedDescription }
        }
    }

    private func leave() {
        guard let baby = currentBaby else { return }
        Task {
            do {
                try await engine.leave(baby, in: modelContext)
                inviteCode = nil
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

#Preview {
    NavigationStack {
        FamilyView()
    }
    .environment(AppRouter())
    .modelContainer(for: [FeedEntry.self, WeightEntry.self, Baby.self], inMemory: true)
}
