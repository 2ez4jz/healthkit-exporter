import Foundation

struct ExportPayload: Codable {
    var schemaVersion: Int = 1
    var exportedAt: Date = .now
    var range: ExportRange
    var daily: [DailyHealthRecord]
    var workouts: [WorkoutRecord]
}

struct ExportRange: Codable {
    let start: Date
    let end: Date
}

struct DailyHealthRecord: Codable, Identifiable {
    var id: String { date }
    let date: String
    var body: BodyMetrics
    var activity: ActivityMetrics
    var sleep: SleepMetrics
}

struct BodyMetrics: Codable {
    var weightKg: Double?
    var vo2max: Double?
    var restingHeartRateBpm: Double?
}

struct ActivityMetrics: Codable {
    var steps: Double?
    var activeCaloriesKcal: Double?
    var exerciseMinutes: Double?
    var walkingRunningDistanceKm: Double?
}

struct SleepMetrics: Codable {
    var asleepHours: Double?
}

struct WorkoutRecord: Codable, Identifiable {
    let id: String
    let type: String
    let start: Date
    let end: Date
    let durationMinutes: Double
    var distanceKm: Double?
    var activeCaloriesKcal: Double?
    var averageHeartRateBpm: Double?
    var sourceName: String?
}
