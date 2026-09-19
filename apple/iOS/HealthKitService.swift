import Foundation
import HealthKit
import CoreMotion
import UserNotifications

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
    private struct StepRewardConfiguration: Codable {
        var enabled = false
        var goalSteps = 8_000
        var maxMinutes = 60
    }

    private struct SleepSummary {
        let hours: Double
        let start: Date?
        let end: Date?
    }

    private let store = HKHealthStore()
    private let pedometer = CMPedometer()
    private let notificationCenter = UNUserNotificationCenter.current()
    private let automationDefaults = UserDefaults(suiteName: "group.com.bojangles4x4.DailyRoutine") ?? .standard
    private let automationConfigurationKey = "dailyRoutine.health.stepRewards.configuration.v1"
    private let automationDayKey = "dailyRoutine.health.stepRewards.notificationDay.v1"
    private let automationMilestoneKey = "dailyRoutine.health.stepRewards.notificationMilestone.v1"
    private var stepObserver: HKObserverQuery?

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
        if loadStepRewardConfiguration().enabled { activateStepRewardAutomation() }
    }

    func restoreStepRewardAutomation() {
        guard loadStepRewardConfiguration().enabled else { return }
        activateStepRewardAutomation()
    }

    func configureStepRewards(enabled: Bool, goalSteps: Int, maxMinutes: Int) async {
        let configuration = StepRewardConfiguration(
            enabled: enabled,
            goalSteps: min(30_000, max(1_000, goalSteps)),
            maxMinutes: min(120, max(15, maxMinutes))
        )
        if let data = try? JSONEncoder().encode(configuration) {
            automationDefaults.set(data, forKey: automationConfigurationKey)
        }
        guard enabled else {
            if let stepObserver { store.stop(stepObserver) }
            stepObserver = nil
            if let stepType { store.disableBackgroundDelivery(for: stepType) { _, _ in } }
            return
        }
        let authorization = await notificationCenter.notificationSettings().authorizationStatus
        if authorization == .notDetermined {
            _ = try? await notificationCenter.requestAuthorization(options: [.alert, .sound])
        }
        activateStepRewardAutomation()
        await processStepRewardUpdate(configuration: configuration)
    }

    private func loadStepRewardConfiguration() -> StepRewardConfiguration {
        guard
            let data = automationDefaults.data(forKey: automationConfigurationKey),
            let configuration = try? JSONDecoder().decode(StepRewardConfiguration.self, from: data)
        else { return StepRewardConfiguration() }
        return configuration
    }

    private func activateStepRewardAutomation() {
        guard let stepType else { return }
        if stepObserver == nil {
            let query = HKObserverQuery(sampleType: stepType, predicate: nil) { [weak self] _, completion, error in
                guard error == nil else {
                    completion()
                    return
                }
                Task { @MainActor [weak self] in
                    await self?.processStepRewardUpdate()
                    completion()
                }
            }
            stepObserver = query
            store.execute(query)
        }
        store.enableBackgroundDelivery(for: stepType, frequency: .immediate) { _, _ in }
    }

    private func processStepRewardUpdate(configuration: StepRewardConfiguration? = nil, now: Date = Date()) async {
        let configuration = configuration ?? loadStepRewardConfiguration()
        guard configuration.enabled, let steps = try? await fetchSteps(now: now) else { return }
        let earned = min(configuration.maxMinutes, Int(floor((min(steps, Double(configuration.goalSteps)) / Double(configuration.goalSteps)) * Double(configuration.maxMinutes))))
        let milestone = (earned / 15) * 15
        let day = Self.localDateKey(now)
        let savedDay = automationDefaults.string(forKey: automationDayKey) ?? ""
        let previousMilestone = savedDay == day ? automationDefaults.integer(forKey: automationMilestoneKey) : 0
        if savedDay != day {
            automationDefaults.set(day, forKey: automationDayKey)
            automationDefaults.set(0, forKey: automationMilestoneKey)
        }
        guard milestone >= 15, milestone > previousMilestone else { return }
        automationDefaults.set(milestone, forKey: automationMilestoneKey)

        let settings = await notificationCenter.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
        let content = UNMutableNotificationContent()
        content.title = "Earned Apps time added"
        content.body = "Your walking progress has earned \(milestone) of \(configuration.maxMinutes) minutes today."
        content.sound = .default
        content.threadIdentifier = "earned-access-walking"
        let request = UNNotificationRequest(
            identifier: "dailyRoutine.walking.\(day).\(milestone)",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        )
        try? await notificationCenter.add(request)
    }

    private static func localDateKey(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = .current
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    func fetchSummary(now: Date = Date(), roundStartedAt: Date? = nil) async throws -> HealthSummary {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw HealthKitServiceError.unavailable
        }

        async let steps = fetchSteps(now: now)
        async let stepSampleEnd = fetchLatestStepSampleEnd(now: now)
        async let deviceStepsSinceStart = fetchDeviceSteps(from: roundStartedAt, to: now)
        async let sleep = fetchRecentSleep(now: now)
        async let workouts = fetchWorkoutCount(now: now)
        async let sources = fetchSourceNames(now: now)

        return try await HealthSummary(
            date: now,
            stepCount: steps,
            stepSampleEnd: stepSampleEnd,
            deviceStepsSinceStart: deviceStepsSinceStart,
            sleepHours: sleep.hours,
            workoutCount: workouts,
            sleepStart: sleep.start,
            sleepEnd: sleep.end,
            sourceNames: sources
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

    private func fetchLatestStepSampleEnd(now: Date) async throws -> Date? {
        guard let stepType else { throw HealthKitServiceError.missingType }
        let start = Calendar.current.startOfDay(for: now)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: now)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: stepType,
                predicate: predicate,
                limit: 1,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)]
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: samples?.first?.endDate)
            }
            store.execute(query)
        }
    }

    private func fetchDeviceSteps(from start: Date?, to end: Date) async -> Double? {
        guard let start, start < end, CMPedometer.isStepCountingAvailable() else { return nil }
        return await withCheckedContinuation { continuation in
            pedometer.queryPedometerData(from: start, to: end) { data, error in
                guard error == nil, let data else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: data.numberOfSteps.doubleValue)
            }
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

    private func fetchSourceNames(now: Date) async throws -> [String] {
        let start = Calendar.current.date(byAdding: .hour, value: -36, to: now) ?? Calendar.current.startOfDay(for: now)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: now)
        var names = Set<String>()

        if let stepType {
            let stepSamples: [HKQuantitySample] = try await samples(type: stepType, predicate: predicate)
            stepSamples.forEach { names.insert($0.sourceRevision.source.name) }
        }
        if let sleepType {
            let sleepSamples: [HKCategorySample] = try await samples(type: sleepType, predicate: predicate)
            sleepSamples.forEach { names.insert($0.sourceRevision.source.name) }
        }
        let workouts: [HKWorkout] = try await samples(type: .workoutType(), predicate: predicate)
        workouts.forEach { names.insert($0.sourceRevision.source.name) }

        return names.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.sorted()
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
