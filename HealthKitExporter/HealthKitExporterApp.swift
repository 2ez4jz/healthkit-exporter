import SwiftUI

@main
struct HealthKitExporterApp: App {
    @StateObject private var store = ExporterStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
        }
    }
}
