import Foundation
import HealthKit

final class HealthKitManager {
    static let shared = HealthKitManager()

    private let healthStore = HKHealthStore()
    private let calendar = Calendar.current

    enum HealthError: LocalizedError {
        case unavailable
        case missingType(String)

        var errorDescription: String? {
            switch self {
            case .unavailable:
                return "Health data is unavailable on this device."
            case .missingType(let name):
                return "HealthKit type is unavailable: \(name)"
            }
        }
    }

    var isHealthDataAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    func requestAuthorization() async throws {
        guard isHealthDataAvailable else { throw HealthError.unavailable }

        let readTypes = try requestedReadTypes()
        try await healthStore.requestAuthorization(toShare: [], read: readTypes)
    }

    private func requestedReadTypes() throws -> Set<HKObjectType> {
        var types = Set<HKObjectType>()

        let quantityIdentifiers: [HKQuantityTypeIdentifier] = [
            .stepCount,
            .activeEnergyBurned,
            .appleExerciseTime,
            .distanceWalkingRunning,
            .bodyMass,
            .vo2Max,
            .restingHeartRate,
            .heartRate
        ]

        for identifier in quantityIdentifiers {
            guard let type = HKObjectType.quantityType(forIdentifier: identifier) else {
                throw HealthError.missingType(identifier.rawValue)
            }
            types.insert(type)
        }

        guard let sleep = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else {
            throw HealthError.missingType(HKCategoryTypeIdentifier.sleepAnalysis.rawValue)
        }

        types.insert(sleep)
        types.insert(HKObjectType.workoutType())
        return types
    }

    func export(from startDate: Date, to endDate: Date) async throws -> ExportPayload {
        let start = calendar.startOfDay(for: startDate)
        let end = endDate

        async let steps = dailyCumulative(.stepCount, unit: .count(), start: start, end: end)
        async let activeCalories = dailyCumulative(.activeEnergyBurned, unit: .kilocalorie(), start: start, end: end)
        async let exerciseMinutes = dailyCumulative(.appleExerciseTime, unit: .minute(), start: start, end: end)
        async let distance = dailyCumulative(.distanceWalkingRunning, unit: .meterUnit(with: .kilo), start: start, end: end)
        async let weight = dailyMostRecent(.bodyMass, unit: .gramUnit(with: .kilo), start: start, end: end)
        async let vo2max = dailyMostRecent(.vo2Max, unit: HKUnit(from: "ml/kg*min"), start: start, end: end)
        async let restingHR = dailyMostRecent(.restingHeartRate, unit: HKUnit.count().unitDivided(by: .minute()), start: start, end: end)
        async let sleep = dailySleep(start: start, end: end)
        async let workouts = fetchWorkouts(start: start, end: end)

        let allSteps = try await steps
        let allActive = try await activeCalories
        let allExercise = try await exerciseMinutes
        let allDistance = try await distance
        let allWeight = try await weight
        let allVO2 = try await vo2max
        let allRHR = try await restingHR
        let allSleep = try await sleep
        let allWorkouts = try await workouts

        let dayStarts = daysBetween(start: start, end: end)
        let formatter = Self.dayFormatter

        let daily = dayStarts.map { day -> DailyHealthRecord in
            let key = formatter.string(from: day)
            return DailyHealthRecord(
                date: key,
                body: BodyMetrics(
                    weightKg: allWeight[key],
                    vo2max: allVO2[key],
                    restingHeartRateBpm: allRHR[key]
                ),
                activity: ActivityMetrics(
                    steps: allSteps[key],
                    activeCaloriesKcal: allActive[key],
                    exerciseMinutes: allExercise[key],
                    walkingRunningDistanceKm: allDistance[key]
                ),
                sleep: SleepMetrics(asleepHours: allSleep[key])
            )
        }

        return ExportPayload(
            exportedAt: .now,
            range: ExportRange(start: start, end: end),
            daily: daily,
            workouts: allWorkouts
        )
    }

    private func dailyCumulative(
        _ identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        start: Date,
        end: Date
    ) async throws -> [String: Double] {
        guard let type = HKObjectType.quantityType(forIdentifier: identifier) else {
            throw HealthError.missingType(identifier.rawValue)
        }

        return try await withCheckedThrowingContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
            let anchor = calendar.startOfDay(for: start)
            let interval = DateComponents(day: 1)

            let query = HKStatisticsCollectionQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum,
                anchorDate: anchor,
                intervalComponents: interval
            )

            query.initialResultsHandler = { _, collection, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                var output: [String: Double] = [:]
                collection?.enumerateStatistics(from: start, to: end) { stats, _ in
                    guard let sum = stats.sumQuantity() else { return }
                    let key = Self.dayFormatter.string(from: stats.startDate)
                    output[key] = sum.doubleValue(for: unit)
                }
                continuation.resume(returning: output)
            }
            healthStore.execute(query)
        }
    }

    private func dailyMostRecent(
        _ identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        start: Date,
        end: Date
    ) async throws -> [String: Double] {
        guard let type = HKObjectType.quantityType(forIdentifier: identifier) else {
            throw HealthError.missingType(identifier.rawValue)
        }

        return try await withCheckedThrowingContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [sort]) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                var output: [String: Double] = [:]
                for case let sample as HKQuantitySample in samples ?? [] {
                    let key = Self.dayFormatter.string(from: sample.startDate)
                    output[key] = sample.quantity.doubleValue(for: unit)
                }
                continuation.resume(returning: output)
            }
            healthStore.execute(query)
        }
    }

    private func dailySleep(start: Date, end: Date) async throws -> [String: Double] {
        guard let type = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else {
            throw HealthError.missingType(HKCategoryTypeIdentifier.sleepAnalysis.rawValue)
        }

        return try await withCheckedThrowingContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [sort]) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                var output: [String: Double] = [:]

                for case let sample as HKCategorySample in samples ?? [] {
                    guard Self.isAsleep(sample.value) else { continue }
                    let key = Self.dayFormatter.string(from: sample.endDate)
                    let hours = sample.endDate.timeIntervalSince(sample.startDate) / 3600
                    output[key, default: 0] += hours
                }
                continuation.resume(returning: output)
            }
            healthStore.execute(query)
        }
    }

    private func fetchWorkouts(start: Date, end: Date) async throws -> [WorkoutRecord] {
        let workoutType = HKObjectType.workoutType()

        let workouts: [HKWorkout] = try await withCheckedThrowingContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

            let query = HKSampleQuery(sampleType: workoutType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [sort]) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: (samples as? [HKWorkout]) ?? [])
            }
            healthStore.execute(query)
        }

        var result: [WorkoutRecord] = []
        for workout in workouts {
            let avgHR = try await averageHeartRate(for: workout)
            result.append(
                WorkoutRecord(
                    id: workout.uuid.uuidString,
                    type: workout.workoutActivityType.displayName,
                    start: workout.startDate,
                    end: workout.endDate,
                    durationMinutes: workout.duration / 60,
                    distanceKm: workout.totalDistance?.doubleValue(for: .meterUnit(with: .kilo)),
                    activeCaloriesKcal: workout.totalEnergyBurned?.doubleValue(for: .kilocalorie()),
                    averageHeartRateBpm: avgHR,
                    sourceName: workout.sourceRevision.source.name
                )
            )
        }

        return result
    }

    private func averageHeartRate(for workout: HKWorkout) async throws -> Double? {
        guard let heartRateType = HKObjectType.quantityType(forIdentifier: .heartRate) else {
            return nil
        }

        return try await withCheckedThrowingContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(withStart: workout.startDate, end: workout.endDate)
            let query = HKStatisticsQuery(quantityType: heartRateType, quantitySamplePredicate: predicate, options: .discreteAverage) { _, stats, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let unit = HKUnit.count().unitDivided(by: .minute())
                continuation.resume(returning: stats?.averageQuantity()?.doubleValue(for: unit))
            }
            healthStore.execute(query)
        }
    }

    private func daysBetween(start: Date, end: Date) -> [Date] {
        var days: [Date] = []
        var cursor = calendar.startOfDay(for: start)
        let last = calendar.startOfDay(for: end)

        while cursor <= last {
            days.append(cursor)
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return days
    }

    private static func isAsleep(_ value: Int) -> Bool {
        if #available(iOS 16.0, *) {
            return [
                HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
                HKCategoryValueSleepAnalysis.asleepCore.rawValue,
                HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
                HKCategoryValueSleepAnalysis.asleepREM.rawValue
            ].contains(value)
        }
        return value == HKCategoryValueSleepAnalysis.asleep.rawValue
    }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_CA")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
}

private extension HKWorkoutActivityType {
    var displayName: String {
        switch self {
        case .running: return "Running"
        case .walking: return "Walking"
        case .traditionalStrengthTraining: return "Strength Training"
        case .functionalStrengthTraining: return "Functional Strength"
        case .highIntensityIntervalTraining: return "HIIT"
        case .cycling: return "Cycling"
        case .swimming: return "Swimming"
        case .hiking: return "Hiking"
        case .yoga: return "Yoga"
        case .elliptical: return "Elliptical"
        case .stairClimbing: return "Stair Climbing"
        default: return "Workout (\(rawValue))"
        }
    }
}
