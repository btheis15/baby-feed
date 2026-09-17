import SwiftUI

/// What the baby can eat now, what's still off the menu, and when that changes.
///
/// Built for the stretch after the strict every-three-hours phase, when the
/// question stops being "how much" and starts being "can she have this?".
struct FoodsView: View {
    /// Age in whole months, or nil when the birthday isn't set.
    let ageMonths: Int?
    let babyName: String

    private var stage: FoodGuidance.Stage? { ageMonths.map(FoodGuidance.stage(forMonths:)) }

    var body: some View {
        List {
            if let ageMonths, let stage {
                nowSection(stage: stage, months: ageMonths)
                if stage.id == "watch-for-readiness" || stage.id == "milk-only" {
                    readinessSection
                }
                stillAvoidSection(months: ageMonths)
                clearedSection(months: ageMonths)
                comingUpSection(months: ageMonths)
            } else {
                Section {
                    Text("Set \(babyName)'s birthday in the Baby tab and this becomes a list for their age.")
                        .foregroundStyle(.secondary)
                }
                allStagesSection
            }
            emergingSection
            sourcesSection
        }
        .navigationTitle("Foods by age")
    }

    // MARK: Still-moving evidence

    private var emergingSection: some View {
        Section {
            ForEach(FoodGuidance.emergingTopics) { topic in
                DisclosureGroup {
                    VStack(alignment: .leading, spacing: 10) {
                        labelled("Current advice", topic.established, tint: .green)
                        labelled("Newer evidence", topic.emerging, tint: .blue)
                        labelled("The catch", topic.limitation, tint: .orange)

                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(topic.citations) { citation in
                                Link(destination: citation.url) {
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(citation.title)
                                            .font(.caption.weight(.medium))
                                        Text(citation.authors)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                        Text(citation.publication)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    .multilineTextAlignment(.leading)
                                }
                            }
                        }
                        .padding(.top, 2)
                    }
                    .padding(.vertical, 4)
                } label: {
                    Text(topic.question)
                        .font(.subheadline)
                }
            }
        } header: {
            Label("Where the evidence is still moving", systemImage: "flask")
        } footer: {
            Text(FoodGuidance.emergingDisclaimer)
        }
    }

    private func labelled(_ title: String, _ body: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(tint)
            Text(body)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Now

    private func nowSection(stage: FoodGuidance.Stage, months: Int) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                Text(stage.title)
                    .font(.headline)
                Text(stage.summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 2)

            // A neutral bullet, not a green tick: these lines describe the
            // stage, and some of them are prohibitions ("No plain water"),
            // where a tick would read as approval. Text rather than an Image so
            // it scales with Dynamic Type, and hidden from VoiceOver so it
            // isn't announced before every line.
            ForEach(stage.canEat, id: \.self) { item in
                Label {
                    Text(item)
                } icon: {
                    Text("•")
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
                .font(.subheadline)
            }
        } header: {
            Text("At \(monthsText(months)) · \(stage.ageText)")
        }
    }

    private var readinessSection: some View {
        Section {
            ForEach(FoodGuidance.readinessSigns, id: \.self) { sign in
                Label {
                    Text(sign)
                } icon: {
                    Image(systemName: "circle.dashed")
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
                .font(.subheadline)
            }
        } header: {
            Text("Signs of readiness")
        } footer: {
            Text("Readiness is about development, not a birthday. The AAP looks for most of these together before starting solids, and advises against starting before 4 months.")
        }
    }

    // MARK: Avoid

    private func stillAvoidSection(months: Int) -> some View {
        let rules = FoodGuidance.rules(applyingAtMonths: months)
        return Section {
            ForEach(rules) { rule in
                DisclosureGroup {
                    Text(rule.detail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    if let afterwards = rule.afterwards {
                        Text(afterwards)
                            .font(.footnote)
                            .foregroundStyle(.green)
                    }
                } label: {
                    LabeledContent {
                        Text(rule.ageText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } label: {
                        Label {
                            Text(rule.food)
                        } icon: {
                            Image(systemName: icon(for: rule.reason))
                                .foregroundStyle(tint(for: rule.reason))
                        }
                    }
                    // The reason is carried by icon and colour, which VoiceOver
                    // can't see, so say it.
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(rule.food), \(rule.reason.rawValue), \(rule.ageText)")
                }
            }
        } header: {
            Text("Not yet")
        } footer: {
            Text("Tap any item for the reason and when it changes.")
        }
    }

    private func clearedSection(months: Int) -> some View {
        let cleared = FoodGuidance.rules(clearedByMonths: months)
        return Group {
            if !cleared.isEmpty {
                Section {
                    ForEach(cleared) { rule in
                        VStack(alignment: .leading, spacing: 2) {
                            Label {
                                Text(rule.food)
                            } icon: {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            }
                            if let afterwards = rule.afterwards {
                                Text(afterwards)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("Now fine")
                }
            }
        }
    }

    private func comingUpSection(months: Int) -> some View {
        let upcoming = FoodGuidance.stages.filter { $0.fromMonths > months }
        return Group {
            if !upcoming.isEmpty {
                Section {
                    ForEach(upcoming) { stage in
                        LabeledContent {
                            Text("\(stage.fromMonths) mo")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(stage.title)
                                Text(stage.summary)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("Coming up")
                }
            }
        }
    }

    private var allStagesSection: some View {
        Section {
            ForEach(FoodGuidance.stages) { stage in
                VStack(alignment: .leading, spacing: 2) {
                    LabeledContent {
                        Text(stage.ageText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } label: {
                        Text(stage.title)
                    }
                    Text(stage.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("The stages")
        }
    }

    // MARK: Sources

    private var sourcesSection: some View {
        Section {
            ForEach(FoodGuidance.sources) { source in
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
        } footer: {
            Text("Guidance from the American Academy of Pediatrics, the CDC and the World Health Organization. It's a starting point, not a prescription – your pediatrician knows \(babyName) and has the final say.")
        }
    }

    // MARK: Helpers

    private func monthsText(_ months: Int) -> String {
        months == 1 ? "1 month" : "\(months) months"
    }

    private func icon(for reason: FoodGuidance.AvoidReason) -> String {
        switch reason {
        case .safety: "exclamationmark.triangle.fill"
        case .choking: "exclamationmark.octagon.fill"
        case .nutrition: "minus.circle.fill"
        }
    }

    private func tint(for reason: FoodGuidance.AvoidReason) -> Color {
        switch reason {
        case .safety: .red
        case .choking: .orange
        case .nutrition: .secondary
        }
    }
}

#Preview("6 months") {
    NavigationStack {
        FoodsView(ageMonths: 6, babyName: "Sam")
    }
}

#Preview("No birthday") {
    NavigationStack {
        FoodsView(ageMonths: nil, babyName: "Baby")
    }
}
