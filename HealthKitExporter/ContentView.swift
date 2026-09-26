import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: ExporterStore

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    statusCard
                    actions
                    latestExport
                    scopeCard
                }
                .padding(20)
            }
            .navigationTitle("Health Sync")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("APPLE HEALTH EXPORTER")
                .font(.caption2.weight(.semibold))
                .tracking(1.6)
                .foregroundStyle(.secondary)

            Text("Your Health data, in your own JSON.")
                .font(.largeTitle.bold())

            Text("First import history, then sync only new data. Nothing is uploaded in this version.")
                .foregroundStyle(.secondary)
        }
    }

    private var statusCard: some View {
        GroupBox {
            HStack(alignment: .top) {
                Image(systemName: store.isAuthorized ? "checkmark.circle.fill" : "heart.text.square")
                    .font(.title2)
                VStack(alignment: .leading, spacing: 5) {
                    Text(store.status)
                        .font(.headline)
                    if let last = store.lastSyncDate {
                        Text("Last sync: \(last.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if store.isBusy {
                    ProgressView()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var actions: some View {
        VStack(spacing: 10) {
            Button {
                Task { await store.authorize() }
            } label: {
                Label("Grant Health Access", systemImage: "lock.open")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)

            Button {
                Task { await store.importHistory() }
            } label: {
                Label("Import History", systemImage: "clock.arrow.circlepath")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(store.isBusy)

            HStack {
                Button("Sync Today") {
                    Task { await store.syncToday() }
                }
                .buttonStyle(.bordered)

                Button("Sync Since Last Run") {
                    Task { await store.syncSinceLastRun() }
                }
                .buttonStyle(.bordered)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var latestExport: some View {
        if let payload = store.lastPayload {
            GroupBox("Latest export") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("\(payload.daily.count) daily records")
                    Text("\(payload.workouts.count) workouts")
                    if let url = store.lastFileURL {
                        Text(url.lastPathComponent)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                        ShareLink(item: url) {
                            Label("Share JSON", systemImage: "square.and.arrow.up")
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var scopeCard: some View {
        GroupBox("V0.1 data scope") {
            VStack(alignment: .leading, spacing: 6) {
                Label("Steps, active calories, exercise minutes, walking/running distance", systemImage: "figure.walk")
                Label("Weight, VO₂max, resting heart rate, sleep", systemImage: "heart")
                Label("Workouts: type, time, duration, distance, energy, average HR", systemImage: "figure.run")
            }
            .font(.subheadline)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
