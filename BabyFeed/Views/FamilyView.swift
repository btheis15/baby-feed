import SwiftData
import SwiftUI

/// Caregivers and sync. There's no server yet, so this says where the data
/// actually lives and what sharing will need, rather than offering a sign-in
/// that can't lead anywhere.
struct FamilyView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var babies: [Baby]
    @AppStorage(AppSettings.currentBabyIDKey) private var currentBabyIDRaw = ""
    @AppStorage(AppSettings.displayNameKey) private var displayName = ""

    private var activeBabies: [Baby] { babies.filter { $0.deletedAt == nil } }

    var body: some View {
        List {
            Section {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Everything is on this iPhone")
                            .font(.subheadline.weight(.medium))
                        Text("The log lives in this app, works with no signal, and isn't uploaded anywhere.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "iphone")
                        .foregroundStyle(.green)
                }
            } header: {
                Text("Where your data is")
            }

            Section {
                TextField("Your name", text: $displayName)
                    .textInputAutocapitalization(.words)
            } header: {
                Text("Who's logging")
            } footer: {
                Text("Saved with each feed, so a shared log can show who did what. It stays on this phone until sharing exists.")
            }

            if activeBabies.count > 1 {
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

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Sharing with another caregiver isn't built yet.")
                        .font(.subheadline)
                    Text("The plan is a small server you host yourself, holding only what two phones need to agree – not an account with a company. Each phone keeps its own copy as the source of truth and carries on working offline.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Text("Until then, the pediatrician summary under History shares as plain text to anyone who needs it.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
            } header: {
                Text("Sharing")
            }
        }
        .navigationTitle("Caregivers")
    }
}

#Preview {
    NavigationStack {
        FamilyView()
    }
    .modelContainer(for: [FeedEntry.self, WeightEntry.self, Baby.self, CareNote.self], inMemory: true)
}
