import Foundation
import HealthKit

/// Apple Health, read only: daily steps, workouts and body weight. Nothing is written to Health and nothing leaves the phone.
/// iOS never tells an app whether read access was granted, so a missing value just means "nothing found".
enum HealthService {
    private static let store = HKHealthStore()

    static var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    private static var stepType: HKQuantityType? { HKQuantityType.quantityType(forIdentifier: .stepCount) }
    private static var weightType: HKQuantityType? { HKQuantityType.quantityType(forIdentifier: .bodyMass) }

    /// Shows the iPhone's Health permission sheet. Returns false only when Health isn't available or the request errored.
    static func requestAccess() async -> Bool {
        guard isAvailable, let steps = stepType, let weight = weightType else { return false }
        var types: Set<HKObjectType> = [steps, weight, HKObjectType.workoutType()]
        if let energy = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) { types.insert(energy) }
        do {
            try await store.requestAuthorization(toShare: [], read: types)
            return true
        } catch {
            return false
        }
    }

    /// Average steps a day over the last full `days` days, counting only days that have data.
    static func averageDailySteps(days: Int = 7) async -> Int? {
        guard isAvailable, let type = stepType else { return nil }
        let calendar = Calendar.current
        let end = calendar.startOfDay(for: .now)
        guard let start = calendar.date(byAdding: .day, value: -days, to: end) else { return nil }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        return await withCheckedContinuation { continuation in
            let query = HKStatisticsCollectionQuery(quantityType: type, quantitySamplePredicate: predicate,
                                                    options: .cumulativeSum, anchorDate: start,
                                                    intervalComponents: DateComponents(day: 1))
            query.initialResultsHandler = { _, results, _ in
                var totals: [Double] = []
                results?.enumerateStatistics(from: start, to: end) { statistics, _ in
                    if let sum = statistics.sumQuantity()?.doubleValue(for: HKUnit.count()), sum > 0 { totals.append(sum) }
                }
                if totals.isEmpty {
                    continuation.resume(returning: nil)
                } else {
                    continuation.resume(returning: Int((totals.reduce(0, +) / Double(totals.count)).rounded()))
                }
            }
            store.execute(query)
        }
    }

    /// The most recent body weight in Health, in kilograms.
    static func latestWeightKg() async -> Double? {
        guard isAvailable, let type = weightType else { return nil }
        let newestFirst = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: nil, limit: 1, sortDescriptors: [newestFirst]) { _, samples, _ in
                let kg = (samples?.first as? HKQuantitySample)?.quantity.doubleValue(for: HKUnit.gramUnit(with: .kilo))
                continuation.resume(returning: kg)
            }
            store.execute(query)
        }
    }

    // MARK: Week at a glance

    struct DailySteps: Identifiable, Sendable {
        let date: Date
        let steps: Int
        var id: Date { date }
    }

    struct Workout: Identifiable, Sendable {
        let id: UUID
        let name: String
        let start: Date
        let minutes: Int
        let kcal: Int?
    }

    /// Steps for each of the last `days` full days, oldest first. Days with no data show as 0.
    static func dailySteps(days: Int = 7) async -> [DailySteps] {
        guard isAvailable, let type = stepType else { return [] }
        let calendar = Calendar.current
        let end = calendar.startOfDay(for: .now)
        guard let start = calendar.date(byAdding: .day, value: -days, to: end) else { return [] }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        return await withCheckedContinuation { continuation in
            let query = HKStatisticsCollectionQuery(quantityType: type, quantitySamplePredicate: predicate,
                                                    options: .cumulativeSum, anchorDate: start,
                                                    intervalComponents: DateComponents(day: 1))
            query.initialResultsHandler = { _, results, _ in
                var out: [DailySteps] = []
                results?.enumerateStatistics(from: start, to: end) { statistics, _ in
                    let sum = statistics.sumQuantity()?.doubleValue(for: HKUnit.count()) ?? 0
                    out.append(DailySteps(date: statistics.startDate, steps: Int(sum.rounded())))
                }
                continuation.resume(returning: out)
            }
            store.execute(query)
        }
    }

    /// Workouts and activities recorded in Health (runs, walks, yoga, strength sessions, other apps and watches), newest first.
    static func recentWorkouts(days: Int = 7) async -> [Workout] {
        guard isAvailable else { return [] }
        let start = Calendar.current.date(byAdding: .day, value: -days, to: .now) ?? .now
        let predicate = HKQuery.predicateForSamples(withStart: start, end: nil)
        let newestFirst = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: HKObjectType.workoutType(), predicate: predicate, limit: 60,
                                      sortDescriptors: [newestFirst]) { _, samples, _ in
                let workouts = (samples as? [HKWorkout] ?? []).map { w in
                    Workout(id: w.uuid, name: activityName(w.workoutActivityType), start: w.startDate,
                            minutes: max(1, Int((w.duration / 60).rounded())), kcal: activeEnergy(w))
                }
                continuation.resume(returning: workouts)
            }
            store.execute(query)
        }
    }

    private static func activeEnergy(_ workout: HKWorkout) -> Int? {
        guard let type = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned),
              let sum = workout.statistics(for: type)?.sumQuantity() else { return nil }
        return Int(sum.doubleValue(for: HKUnit.kilocalorie()).rounded())
    }

    static func activityName(_ type: HKWorkoutActivityType) -> String {
        switch type {
        case .running: return "Run"
        case .walking: return "Walk"
        case .hiking: return "Hike"
        case .cycling: return "Ride"
        case .swimming: return "Swim"
        case .yoga: return "Yoga"
        case .pilates: return "Pilates"
        case .traditionalStrengthTraining, .functionalStrengthTraining: return "Strength"
        case .highIntensityIntervalTraining: return "HIIT"
        case .elliptical: return "Elliptical"
        case .rowing: return "Rowing"
        case .stairClimbing: return "Stairs"
        case .dance, .socialDance, .cardioDance: return "Dance"
        case .coreTraining: return "Core"
        case .flexibility: return "Stretching"
        case .mindAndBody: return "Mind and body"
        case .crossTraining: return "Cross training"
        case .tennis: return "Tennis"
        case .golf: return "Golf"
        case .cricket: return "Cricket"
        default: return "Workout"
        }
    }
}
