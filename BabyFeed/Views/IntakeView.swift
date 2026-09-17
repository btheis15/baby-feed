import SwiftUI

/// "Is she getting enough?" – the question a per-feed recommendation invites,
/// answered with the things that actually tell you, and the ones that don't.
struct IntakeView: View {
    let babyName: String
    /// Age in days, for the nappy expectations that change fast early on.
    let ageDays: Int?
    /// Today's total and the target, when there's enough to compute them.
    let consumedML: Double
    let targetML: Double?
    let unit: VolumeUnit

    private var sources: [FoodGuidance.Source] {
        IntakeGuidance.sourceIDs.compactMap(FoodGuidance.source)
    }

    var body: some View {
        List {
            headlineSection
            if let targetML { todaySection(targetML: targetML) }
            whatMattersSection
            redFlagsSection
            sourcesSection
        }
        .navigationTitle("Getting enough?")
    }

    // MARK: Headline

    private var headlineSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text("One small feed isn't a problem")
                    .font(.headline)
                Text("Babies take what they need and stop when they're full. Appetite swings through the day, so some feeds are big and some are small – a 1 oz feed after a 4 oz one is ordinary. The recommendation is an average for the whole day, not a quota for each bottle.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("Don't push \(babyName) to finish a bottle. Stop when they turn their head away or relax their hands, even if there's milk left.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 2)
        } footer: {
            Text(IntakeGuidance.bottomLine)
        }
    }

    // MARK: Today

    private func todaySection(targetML: Double) -> some View {
        let percent = targetML > 0 ? Int((consumedML / targetML * 100).rounded()) : 0
        return Section {
            LabeledContent("Today so far") {
                Text(unit.format(milliliters: consumedML))
                    .monospacedDigit()
            }
            LabeledContent("Recommended over 24 h") {
                Text("~\(unit.format(milliliters: targetML))")
                    .monospacedDigit()
            }
            LabeledContent("That's") {
                Text("\(percent)%")
                    .monospacedDigit()
            }
        } header: {
            Text("The number that matters")
        } footer: {
            Text("A day that lands short isn't unusual either – look at the run of days rather than one. If the total is consistently well below this and \(babyName) isn't gaining, that's the thing to raise.")
        }
    }

    // MARK: What matters

    private var whatMattersSection: some View {
        Section {
            ForEach(IntakeGuidance.whatMatters) { signal in
                VStack(alignment: .leading, spacing: 2) {
                    Text(signal.title)
                        .font(.subheadline.weight(.medium))
                    Text(signal.detail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
            }

            if let expectation = IntakeGuidance.diaperExpectation(ageDays: ageDays) {
                Label(expectation, systemImage: "calendar")
                    .font(.footnote)
            }
        } header: {
            Text("What tells you it's going well")
        } footer: {
            Text(IntakeGuidance.diaperCaveat)
        }
    }

    // MARK: Red flags

    private var redFlagsSection: some View {
        Section {
            ForEach(IntakeGuidance.redFlags) { flag in
                Label {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(flag.text)
                            .font(.subheadline)
                        Text(flag.urgency.rawValue)
                            .font(.caption)
                            .foregroundStyle(flag.urgency == .now ? .red : .orange)
                    }
                } icon: {
                    Image(systemName: flag.urgency == .now
                          ? "exclamationmark.triangle.fill"
                          : "phone.fill")
                        .foregroundStyle(flag.urgency == .now ? .red : .orange)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(flag.urgency.rawValue): \(flag.text)")
            }
        } header: {
            Text("When to call")
        } footer: {
            Text("This isn't a diagnosis and it isn't exhaustive. If something feels wrong to you, call – you know \(babyName).")
        }
    }

    private var sourcesSection: some View {
        Section {
            ForEach(sources) { source in
                Link(destination: source.url) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(source.title)
                            .font(.subheadline)
                        Text(source.organisation)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            Text("Sources")
        }
    }
}

#Preview {
    NavigationStack {
        IntakeView(
            babyName: "Sam",
            ageDays: 9,
            consumedML: 400,
            targetML: 555,
            unit: .ounces
        )
    }
}
