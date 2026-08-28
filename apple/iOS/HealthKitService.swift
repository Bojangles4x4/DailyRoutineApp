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
    private struct SleepSummary {
        let hours: Double
        let start: Date?
        let end: Date?
    }

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
            sleepHours: sleep.hours,
            workoutCount: workouts,
            sleepStart: sleep.start,
            sleepEnd: sleep.end
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

    private func fetchRecentSleep(now: Date) async throws -> SleepSummary {
        guard let sleepType else { throw HealthKitServiceError.missingType }
        let startOfToday = Calendar.current.startOfDay(for: now)
        let queryStart = Calendar.current.date(byAdding: .hour, value: -24, to: startOfToday) ?? startOfToday
        let predicate = HKQuery.predicateForSamples(withStart: queryStart, end: now)
        let samples: [HKCategorySample] = try await samples(type: sleepType, predicate: predicate)

        let intervals = samples.compactMap { sample -> DateInterval? in
            guard let value = HKCategoryValueSleepAnalysis(rawValue: sample.value) else { return nil }
            switch value {
            case .asleepUnspecified, .asleepCore, .asleepDeep, .asleepREM:
                return DateInterval(start: sample.startDate, end: sample.endDate)
            default:
                return nil
            }
        }
        let merged = mergeOverlapping(intervals)
        var sessions: [[DateInterval]] = []
        for interval in merged {
            if let lastEnd = sessions.last?.last?.end,
               interval.start.timeIntervalSince(lastEnd) <= 90 * 60 {
                sessions[sessions.count - 1].append(interval)
            } else {
                sessions.append([interval])
            }
        }
        guard let session = sessions.max(by: { left, right in
            let leftDuration = left.reduce(0.0) { $0 + $1.duration }
            let rightDuration = right.reduce(0.0) { $0 + $1.duration }
            if leftDuration == rightDuration { return (left.last?.end ?? .distantPast) < (right.last?.end ?? .distantPast) }
            return leftDuration < rightDuration
        }) else { return SleepSummary(hours: 0, start: nil, end: nil) }
        let seconds = session.reduce(0.0) { $0 + $1.duration }
        return SleepSummary(hours: seconds / 3_600, start: session.first?.start, end: session.last?.end)
    }

    private func mergeOverlapping(_ intervals: [DateInterval]) -> [DateInterval] {
        intervals.sorted { $0.start < $1.start }.reduce(into: []) { merged, next in
            guard let last = merged.last else {
                merged.append(next)
                return
            }
            if next.start <= last.end {
                merged[merged.count - 1] = DateInterval(start: last.start, end: max(last.end, next.end))
            } else {
                merged.append(next)
            }
        }
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
