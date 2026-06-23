import SwiftUI

struct TestingStatsView: View {
    @ObservedObject var locationManager: LocationManager

    var body: some View {
        NavigationStack {
            List {
                liveSessionSection
                patternsSection
                savedSessionsSection
            }
            .navigationTitle("Testing & Stats")
        }
    }

    @ViewBuilder
    private var liveSessionSection: some View {
        Section {
            if locationManager.isTracking {
                statusBadge(
                    title: locationManager.liveRouteStats.isCurrentlyStopped ? "Stopped" : "Moving",
                    color: locationManager.liveRouteStats.isCurrentlyStopped ? .orange : .green
                )

                statRow("Session time", RouteAnalyticsFormatting.duration(locationManager.liveRouteStats.sessionDurationSeconds))
                statRow("Current speed", RouteAnalyticsFormatting.speedMPH(locationManager.liveRouteStats.currentSpeedMPS))
                statRow("GPS samples", "\(locationManager.liveRouteStats.sampleCount)")
            } else if locationManager.activeRoute?.isInProgress == true {
                Text("Route paused — resume on the map tab to keep collecting data.")
                    .foregroundStyle(.secondary)
            } else {
                Text("Start a route on the map tab to collect live movement data.")
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Live Session")
        }
    }

    @ViewBuilder
    private var patternsSection: some View {
        if locationManager.isTracking || locationManager.liveRouteStats.isSessionActive {
            let stats = locationManager.liveRouteStats

            Section("Movement") {
                statRow("Avg moving speed", RouteAnalyticsFormatting.speedMPH(stats.averageMovingSpeedMPS))
                statRow("Max speed", RouteAnalyticsFormatting.speedMPH(stats.maxSpeedMPS))
                statRow("Avg speed change", RouteAnalyticsFormatting.speedMPS(stats.averageSpeedChangeMPS))
                statRow("Avg acceleration", RouteAnalyticsFormatting.acceleration(stats.averageAbsoluteAccelerationMPS2))
                statRow("Time moving", RouteAnalyticsFormatting.duration(stats.totalMovingSeconds))
                statRow("Moving share", RouteAnalyticsFormatting.percent(stats.movingFraction))
            }

            Section("Stops") {
                statRow("Stop count", "\(stats.stopCount)")
                statRow("Time stopped", RouteAnalyticsFormatting.duration(stats.totalStoppedSeconds))
                statRow("Avg stop length", RouteAnalyticsFormatting.duration(stats.averageStopDurationSeconds))
                if stats.isCurrentlyStopped {
                    statRow("Current stop", RouteAnalyticsFormatting.duration(stats.currentStopDurationSeconds))
                }

                if stats.recentStops.isEmpty {
                    Text("No completed stops yet this session.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(stats.recentStops) { stop in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(RouteAnalyticsFormatting.duration(stop.durationSeconds))
                                .font(.subheadline.weight(.semibold))
                            Text(stopTimeRange(stop))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section("Turns & GPS") {
                statRow("Significant turns", "\(stats.significantTurnCount)")
                statRow("Avg GPS accuracy", String(format: "%.0f m", stats.averageHorizontalAccuracyMeters))
            }
        }
    }

    @ViewBuilder
    private var savedSessionsSection: some View {
        Section {
            if locationManager.savedRouteAnalytics.isEmpty {
                Text("Completed routes with analytics will appear here after you end a route.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(locationManager.savedRouteAnalytics) { snapshot in
                    NavigationLink {
                        RouteAnalyticsDetailView(snapshot: snapshot)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(snapshot.routeName ?? "Unnamed route")
                                .font(.subheadline.weight(.semibold))
                            Text(savedSessionSubtitle(snapshot))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .onDelete(perform: locationManager.deleteRouteAnalytics)
            }
        } header: {
            Text("Saved Route Analytics")
        } footer: {
            Text("High-frequency GPS samples are analyzed during recording to help tune auto-counting and walking patterns. Stops use speeds below ~0.9 mph.")
                .foregroundStyle(.secondary)
        }
    }

    private func statRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }

    private func statusBadge(title: String, color: Color) -> some View {
        HStack {
            Circle()
                .fill(color)
                .frame(width: 10, height: 10)
            Text(title)
                .font(.subheadline.weight(.semibold))
        }
    }

    private func stopTimeRange(_ stop: RouteStopEvent) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        formatter.dateStyle = .none
        return "\(formatter.string(from: stop.startedAt)) – \(formatter.string(from: stop.endedAt))"
    }

    private func savedSessionSubtitle(_ snapshot: RouteSessionSnapshot) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return "\(formatter.string(from: snapshot.recordedAt)) · \(snapshot.stopCount) stops · \(RouteAnalyticsFormatting.duration(snapshot.sessionDurationSeconds))"
    }
}

struct RouteAnalyticsDetailView: View {
    let snapshot: RouteSessionSnapshot

    var body: some View {
        List {
            Section("Summary") {
                statRow("Duration", RouteAnalyticsFormatting.duration(snapshot.sessionDurationSeconds))
                statRow("Stops", "\(snapshot.stopCount)")
                statRow("Avg stop", RouteAnalyticsFormatting.duration(snapshot.averageStopDurationSeconds))
                statRow("Moving share", RouteAnalyticsFormatting.percent(snapshot.movingFraction))
                statRow("Significant turns", "\(snapshot.significantTurnCount)")
                statRow("GPS samples", "\(snapshot.sampleCount)")
            }

            Section("Speed") {
                statRow("Avg moving speed", RouteAnalyticsFormatting.speedMPH(snapshot.averageMovingSpeedMPS))
                statRow("Max speed", RouteAnalyticsFormatting.speedMPH(snapshot.maxSpeedMPS))
                statRow("Avg speed change", RouteAnalyticsFormatting.speedMPS(snapshot.averageSpeedChangeMPS))
                statRow("Avg acceleration", RouteAnalyticsFormatting.acceleration(snapshot.averageAbsoluteAccelerationMPS2))
            }

            Section("Stops") {
                if snapshot.stops.isEmpty {
                    Text("No stops recorded.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(snapshot.stops) { stop in
                        HStack {
                            Text(RouteAnalyticsFormatting.duration(stop.durationSeconds))
                            Spacer()
                            Text(stopTime(stop))
                                .foregroundStyle(.secondary)
                                .font(.caption)
                        }
                    }
                }
            }
        }
        .navigationTitle(snapshot.routeName ?? "Route Analytics")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func statRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }

    private func stopTime(_ stop: RouteStopEvent) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        formatter.dateStyle = .none
        return formatter.string(from: stop.startedAt)
    }
}

#Preview {
    TestingStatsView(locationManager: LocationManager())
}
