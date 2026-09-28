import Foundation
import SwiftData

/// Every model the app stores, listed once.
///
/// The app's container, the previews and the tests all build their schema
/// from this, so a new model can't be left out of one of them. A preview whose
/// container lacks a model its view queries doesn't fail politely — the canvas
/// crashes — which is how several previews broke once diapers and solid foods
/// arrived and the hand-written lists didn't follow.
enum AppSchema {
    static let models: [any PersistentModel.Type] = [
        FeedEntry.self, WeightEntry.self, Baby.self, CareNote.self,
        DiaperEntry.self, SolidFoodEntry.self,
        HealthConcern.self, Medication.self, MedicationDose.self, DoctorVisit.self,
    ]

    static var schema: Schema { Schema(models) }

    /// A fresh store that lives only in memory, for tests. Named uniquely so
    /// two of them in one process can never share rows.
    static func inMemoryContainer() throws -> ModelContainer {
        let inMemory = Self.schema
        return try ModelContainer(
            for: inMemory,
            configurations: [ModelConfiguration(UUID().uuidString, schema: inMemory, isStoredInMemoryOnly: true)]
        )
    }
}

extension ModelContainer {
    /// Every model, in memory: `.modelContainer(.preview)` in a `#Preview`.
    static let preview: ModelContainer = {
        do {
            return try AppSchema.inMemoryContainer()
        } catch {
            fatalError("Could not create the preview container: \(error)")
        }
    }()
}
