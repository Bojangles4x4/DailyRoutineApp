import Foundation
import HealthKit

enum HealthKitServiceError: LocalizedError {
    case unavailable
    case missingType

    var errorDescription: String? {
        switch self {
        case .unavailable: "Health data is not available on this device."
        case .missingType: "A requested HealthKit data type is unavailable."
        }
    }
}

@MainActor
final class HealthKitService {
    private let store = HKHealthStore()

    var isAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    private var stepType: HKQuantityType? {
        HKObjectType.quantityType(forIdentifier: .stepCount)
    }

    private var sleepType: HKCategoryType? {
        HKObjectType.categoryType(forIdentifier: .sleepAnalysis)
    }

    private var readTypes: Set<HKObjectType> {
        var types: Set<HKObjectType> = [HKObjectType.workoutType()]
        if let stepType { types.insert(stepType) }
        if let sleepType { types.insert(sleepType) }
        return types
    }

    func requestAuthorization() async throws {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw HealthKitServiceError.unavailable
        }
        try await store.requestAuthorization(toShare: [], read: readTypes)
    }

    func fetchSummary(now: Date = Date()) async throws -> HealthSummary {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw HealthKitServiceError.unavailable
        }

        async let steps = fetchSteps(now: now)
        async let sleep = fetchRecentSleep(now: now)
        async let workouts = fetchWorkoutCount(now: now)

        return try await HealthSummary(
            date: now,
            stepCount: steps,
            sleepHours: sleep,
            workoutCount: workouts
        )
    }

    private func fetchSteps(now: Date) async throws -> Double {
        guard let stepType else { throw HealthKitServiceError.missingType }
        let start = Calendar.current.startOfDay(for: now)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: now)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: stepType,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, result, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let value = result?.sumQuantity()?.doubleValue(for: .count()) ?? 0
                continuation.resume(returning: value)
            }
            store.execute(query)
        }
    }

    private func fetchRecentSleep(now: Date) async throws -> Double {
        guard let sleepType else { throw HealthKitServiceError.missingType }
        let startOfToday = Calendar.current.startOfDay(for: now)
        let queryStart = Calendar.current.date(byAdding: .hour, value: -12, to: startOfToday) ?? startOfToday
        let predicate = HKQuery.predicateForSamples(withStart: queryStart, end: now)
        let samples: [HKCategorySample] = try await samples(type: sleepType, predicate: predicate)

        let asleepSeconds = samples.reduce(0.0) { total, sample in
            guard let value = HKCategoryValueSleepAnalysis(rawValue: sample.value) else { return total }
            switch value {
            case .asleepUnspecified, .asleepCore, .asleepDeep, .asleepREM:
                return total + sample.endDate.timeIntervalSince(sample.startDate)
            default:
                return total
            }
        }
        return asleepSeconds / 3_600
    }

    private func fetchWorkoutCount(now: Date) async throws -> Int {
        let start = Calendar.current.startOfDay(for: now)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: now)
        let workouts: [HKWorkout] = try await samples(type: .workoutType(), predicate: predicate)
        return workouts.count
    }

    private func samples<T: HKSample>(type: HKSampleType, predicate: NSPredicate) async throws -> [T] {
        try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: samples as? [T] ?? [])
            }
            store.execute(query)
        }
    }
}
