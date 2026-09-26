import Foundation
import SwiftUI

@MainActor
final class ExporterStore: ObservableObject {
    @Published var isAuthorized = false
    @Published var isBusy = false
    @Published var status = "Not synced yet"
    @Published var lastPayload: ExportPayload?
    @Published var lastFileURL: URL?

    private let manager = HealthKitManager.shared
    private let defaults = UserDefaults.standard

    var lastSyncDate: Date? {
        defaults.object(forKey: "lastSyncDate") as? Date
    }

    func authorize() async {
        isBusy = true
        defer { isBusy = false }

        do {
            try await manager.requestAuthorization()
            isAuthorized = true
            status = "Health access requested"
        } catch {
            status = error.localizedDescription
        }
    }

    func importHistory() async {
        let calendar = Calendar.current
        let fallback = calendar.date(byAdding: .year, value: -10, to: .now) ?? .distantPast
        await sync(from: fallback, to: .now, label: "Historical import")
    }

    func syncToday() async {
        await sync(from: Calendar.current.startOfDay(for: .now), to: .now, label: "Today sync")
    }

    func syncSinceLastRun() async {
        let start = lastSyncDate ?? Calendar.current.date(byAdding: .day, value: -1, to: .now) ?? .now
        await sync(from: start, to: .now, label: "Incremental sync")
    }

    private func sync(from start: Date, to end: Date, label: String) async {
        isBusy = true
        defer { isBusy = false }

        do {
            let payload = try await manager.export(from: start, to: end)
            let file = try Self.write(payload)
            lastPayload = payload
            lastFileURL = file
            defaults.set(Date.now, forKey: "lastSyncDate")
            status = "\(label) complete · \(payload.daily.count) days · \(payload.workouts.count) workouts"
        } catch {
            status = error.localizedDescription
        }
    }

    private static func write(_ payload: ExportPayload) throws -> URL {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        let data = try encoder.encode(payload)
        let fm = FileManager.default
        let directory = fm.urls(for: .documentDirectory, in: .userDomainMask).first!
        let exportDirectory = directory.appendingPathComponent("HealthExports", isDirectory: true)
        try fm.createDirectory(at: exportDirectory, withIntermediateDirectories: true)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HHmmss"
        let filename = "health-export_\(formatter.string(from: .now)).json"
        let url = exportDirectory.appendingPathComponent(filename)
        try data.write(to: url, options: .atomic)
        return url
    }
}
