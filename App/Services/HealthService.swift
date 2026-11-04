import Foundation
import HealthKit

/// Apple Health, read only: daily steps and body weight. Nothing is written to Health and nothing leaves the phone.
/// iOS never tells an app whether read access was granted, so a missing value just means "nothing found".
enum HealthService {
    private static let store = HKHealthStore()

    static var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    private static var stepType: HKQuantityType? { HKQuantityType.quantityType(forIdentifier: .stepCount) }
    private static var weightType: HKQuantityType? { HKQuantityType.quantityType(forIdentifier: .bodyMass) }

    /// Shows the iPhone's Health permission sheet. Returns false only when Health isn't available or the request errored.
    static func requestAccess() async -> Bool {
        guard isAvailable, let steps = stepType, let weight = weightType else { return false }
        do {
            try await store.requestAuthorization(toShare: [], read: [steps, weight])
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
}
