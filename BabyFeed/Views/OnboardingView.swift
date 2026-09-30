import SwiftData
import SwiftUI

/// The first launch: add your baby, join the log someone else already keeps,
/// or bring yours back with a recovery phrase. Nothing to type but the
/// baby's name.
///
/// It's a card with a plain way out, not a wall: "Not now" leaves the app
/// exactly as usable, and everything here is also under Settings.
struct OnboardingView: View {
    private enum Step: Hashable {
        case addBaby, yourName, backUp, join, restore
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(AppRouter.self) private var router
    @AppStorage(AppSettings.weightUnitKey) private var weightUnitRaw = WeightUnit.poundsOunces.rawValue

    @State private var path: [Step] = []

    // The baby
    @State private var draft = NewBabyDraft()

    // The parent
    @State private var yourName = AppSettings.displayName

    // Restoring
    @State private var phraseText = ""
    @State private var keychainPhrases: [String] = []

    @State private var isWorking = false
    @State private var errorMessage: String?

    private var weightUnit: WeightUnit { WeightUnit(rawValue: weightUnitRaw) ?? .poundsOunces }
    private var trimmedBabyName: String { draft.trimmedName }

    var body: some View {
        NavigationStack(path: $path) {
            welcome
                .navigationDestination(for: Step.self) { step in
                    switch step {
                    case .addBaby: addBaby
                    case .yourName: yourNameStep
                    case .backUp: backUp
                    case .join: join
                    case .restore: restore
                    }
                }
        }
        .interactiveDismissDisabled(isWorking)
    }

    // MARK: Welcome

    private var welcome: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 24)
            Image(systemName: "heart.text.square.fill")
                .font(.system(size: 56))
                .foregroundStyle(.tint)
                .padding(.bottom, 18)
                .accessibilityHidden(true)
            Text("Welcome to Baby Feed")
                .font(.largeTitle.bold())
                .multilineTextAlignment(.center)
            Text("Feeds, diapers and the rest, one tap each, and a countdown to the next feed.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .padding(.top, 8)
            Spacer(minLength: 24)

            VStack(spacing: 12) {
                Button {
                    path.append(.addBaby)
                } label: {
                    Text("Add my baby").frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)

                Button {
                    path.append(.join)
                } label: {
                    Text("Join the log").frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
                .controlSize(.large)

                Button("Restore with recovery phrase") {
                    keychainPhrases = RecoveryPhrase.allStored()
                    path.append(.restore)
                }
                .padding(.top, 4)

                Button("Not now") { dismiss() }
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
        }
    }

    // MARK: Adding the baby

    private var addBaby: some View {
        Form {
            NewBabyFields(draft: $draft, weightUnit: weightUnit)
        }
        .navigationTitle("Your baby")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Next") { path.append(.yourName) }
                    .disabled(trimmedBabyName.isEmpty)
            }
        }
    }

    // MARK: The parent's name

    private static let nameChoices = ["Mom", "Dad", "Grandma", "Grandpa", "Nanny"]

    private var yourNameStep: some View {
        Form {
            Section {
                NameChips(choices: Self.nameChoices, name: $yourName)
                    .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
                TextField("Or type a name", text: $yourName)
                    .textInputAutocapitalization(.words)
            } header: {
                Text("What should we call you?")
            } footer: {
                Text("Shown next to everything you log, so a shared log says who did what.")
            }
        }
        .navigationTitle("You")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Next") { afterName() }
            }
        }
    }

    private func afterName() {
        AppSettings.displayName = yourName.trimmingCharacters(in: .whitespacesAndNewlines)
        if SyncEngine.shared.hasServer {
            path.append(.backUp)
        } else {
            // No server in this build: nothing to back up to, and no phrase
            // worth writing down.
            addTheBaby()
            dismiss()
        }
    }

    private var backUp: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "house.fill")
                .font(.system(size: 48))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text("Backed up at home")
                .font(.title2.bold())
            Text("Baby Feed backs \(trimmedBabyName)'s log up to your Mac mini at home, so it's safe if this phone isn't, and so another phone can share it. Your iPhone will ask to let it find devices on your network: that's this.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
            }
            Spacer()
            Button {
                Task { await addAndBackUp() }
            } label: {
                Group {
                    if isWorking { ProgressView() } else { Text("Continue") }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .disabled(isWorking)
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
        }
        .navigationTitle("")
        .navigationBarBackButtonHidden(isWorking)
    }

    @discardableResult
    private func addTheBaby() -> Baby {
        draft.create(weightUnit: weightUnit, in: modelContext)
    }

    private func addAndBackUp() async {
        isWorking = true
        errorMessage = nil
        addTheBaby()
        // Made before connecting, so it can be written down now even if the
        // phone isn't home: the same phrase is registered once it is.
        SyncEngine.shared.preparePhrase()
        do {
            try await SyncEngine.shared.ensureConnected(.addedBaby)
        } catch SyncError.away {
            // Fine: it backs up by itself once the phone is home.
        } catch {
            // Saved on the phone either way; Caregivers says what went wrong.
        }
        isWorking = false
        // Swapping the sheet closes this one and opens the phrase.
        router.sheet = .recoverySetup
    }

    // MARK: Joining

    private var join: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "qrcode.viewfinder")
                .font(.system(size: 56))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text("Join the log")
                .font(.title2.bold())
            VStack(alignment: .leading, spacing: 14) {
                step(1, "On the phone that has the log, tap Share.")
                step(2, "Point this phone's Camera at the code it shows.")
                step(3, "Tap the banner that appears. Baby Feed opens and joins.")
            }
            .padding(.horizontal, 32)
            Text("Both phones need to be on your home Wi‑Fi. Got a link instead? Open it on this phone.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
            Button("Done") { dismiss() }
                .controlSize(.large)
                .padding(.bottom, 16)
        }
        .navigationTitle("")
    }

    private func step(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("\(number)")
                .font(.headline)
                .frame(width: 28, height: 28)
                .background(Color.accentColor.opacity(0.15), in: Circle())
            Text(text)
                .font(.body)
        }
    }

    // MARK: Restoring

    private var restore: some View {
        Form {
            if !keychainPhrases.isEmpty {
                Section {
                    Button {
                        phraseText = keychainPhrases[0]
                        Task { await restoreNow() }
                    } label: {
                        Label("Restore from iCloud Keychain", systemImage: "key.icloud.fill")
                    }
                    .disabled(isWorking)
                } footer: {
                    Text("A recovery phrase from an earlier install is in this iPhone's keychain.")
                }
            }

            Section {
                TextField("XXXX-XXXX-XXXX-XXXX-XXXX-XXXX", text: $phraseText, axis: .vertical)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .font(.system(.body, design: .monospaced))
            } header: {
                Text("Recovery phrase")
            } footer: {
                Text("The \(RecoveryKey.length) letters and numbers you wrote down. Dashes, spaces and capitals don't matter. Be on your home Wi‑Fi.")
            }

            if let errorMessage {
                Section {
                    Text(errorMessage).font(.footnote).foregroundStyle(.red)
                }
            }

            Section {
                Button {
                    Task { await restoreNow() }
                } label: {
                    HStack {
                        Spacer()
                        if isWorking { ProgressView() } else { Text("Restore") }
                        Spacer()
                    }
                }
                .disabled(isWorking || !RecoveryKey.isPlausible(phraseText))
            }
        }
        .navigationTitle("Restore")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func restoreNow() async {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            try await SyncEngine.shared.recover(key: phraseText)
            RecoveryPhraseReminder.confirmed = true
            dismiss()
        } catch let error as SyncError {
            errorMessage = switch error {
            case .server(404, _, _): "That phrase doesn't match any log on your Mac mini. Check it character by character."
            case .away: "Can't reach your Mac mini. Connect to your home Wi‑Fi and try again."
            case .notConfigured: "This build doesn't know your Mac mini's address. Settings → Caregivers & sync → Advanced can take it."
            default: error.errorDescription
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// Mom · Dad · Grandma…: one tap to name who's logging.
struct NameChips: View {
    let choices: [String]
    @Binding var name: String

    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(choices, id: \.self) { choice in
                let selected = name == choice
                Button {
                    name = choice
                } label: {
                    Text(choice)
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(selected ? Color.accentColor : Color(.tertiarySystemFill), in: Capsule())
                        .foregroundStyle(selected ? Color.white : Color.primary)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }
}

/// Lays chips out left to right, wrapping onto new lines.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, widest: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            widest = max(widest, x - spacing)
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: min(widest, width), height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

#Preview {
    OnboardingView()
        .environment(AppRouter())
        .modelContainer(.preview)
}
