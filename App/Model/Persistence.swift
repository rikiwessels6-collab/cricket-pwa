import Foundation
import SwiftData

enum Persistence {
    static let schema = Schema([UserProfile.self, TrainingPlan.self, NutritionPlan.self, CheckInSettings.self, AppSettings.self,
                                 WorkoutLog.self, SetLog.self, FoodEntry.self, SavedFood.self, CheckInEntry.self, ExerciseNote.self, ProgressPhoto.self, CustomExercise.self])

    /// UI tests pass -UITestInMemory to start from a clean, throwaway store.
    static var isUITest: Bool { ProcessInfo.processInfo.arguments.contains("-UITestInMemory") }

    static func makeContainer() -> ModelContainer {
        do {
            if isUITest {
                return try ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
            }
            let dir = try storeDirectory()
            let config = ModelConfiguration(schema: schema, url: dir.appendingPathComponent("SteadyStrength.store"))
            return try ModelContainer(for: schema, configurations: config)
        } catch {
            fatalError("Could not open the data store: \(error)")
        }
    }

    /// Application Support/Store, encrypted by iOS whenever the phone is locked
    /// (complete-unless-open protection: an in-progress save can finish if the phone locks).
    static func storeDirectory() throws -> URL {
        let base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                               appropriateFor: nil, create: true)
        let dir = base.appendingPathComponent("Store", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true,
                                                attributes: [.protectionKey: FileProtectionType.completeUnlessOpen])
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUnlessOpen], ofItemAtPath: dir.path)
        return dir
    }

    /// Deletes every record. Used by "Erase all my data".
    @MainActor
    static func eraseAll(_ context: ModelContext) throws {
        try context.delete(model: UserProfile.self)
        try context.delete(model: TrainingPlan.self)
        try context.delete(model: NutritionPlan.self)
        try context.delete(model: CheckInSettings.self)
        try context.delete(model: FoodEntry.self)
        try context.delete(model: SavedFood.self)
        try context.delete(model: CheckInEntry.self)
        try context.delete(model: ExerciseNote.self)
        try context.delete(model: ProgressPhoto.self)
        try context.delete(model: CustomExercise.self)
        PhotoStore.deleteAll()
        try context.delete(model: SetLog.self)
        try context.delete(model: WorkoutLog.self)
        try context.delete(model: AppSettings.self)
        try context.save()
    }
}
