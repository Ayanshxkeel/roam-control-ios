import MapKit
import SwiftUI

struct PinLookAroundView: View {
    let followsCurrent: Bool
    let selectedPin: SelectedCoordinate
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var phase
    @State private var scene: MKLookAroundScene?
    @State private var sceneID = UUID()
    @State private var loading = true
    @State private var unavailable = ""
    @State private var requested: SelectedCoordinate?
    @State private var loaded: SelectedCoordinate?
    private var target: SelectedCoordinate? { followsCurrent ? model.simulatedCoordinate : selectedPin }

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                if let scene {
                    LookAroundPreview(initialScene: scene).id(sceneID)
                } else if loading { ProgressView("Finding street-level imagery…").frame(maxHeight: .infinity) }
                else { ContentUnavailableView("Look Around unavailable", systemImage: "binoculars", description: Text(unavailable)) }
                VStack(alignment: .leading, spacing: 6) {
                    if let target {
                        Text(String(format: "Requested: %.6f, %.6f", target.latitude, target.longitude)).monospacedDigit()
                    }
                    if loading { Label("Updating imagery…", systemImage: "arrow.triangle.2.circlepath") }
                    if let loaded, followsCurrent {
                        Text(String(format: "Last imagery request: %.6f, %.6f", loaded.latitude, loaded.longitude)).monospacedDigit()
                    }
                    Text("Apple supplies nearby street imagery, not an exact live camera at the pin. Coverage, camera position and image dates vary.")
                    if followsCurrent { Text("Your route continues. Imagery refreshes about every 3 seconds after moving at least 15 metres; it may lag behind the driving pin.") }
                }.font(.caption).foregroundStyle(.secondary).padding(.horizontal)
            }
            .navigationTitle(followsCurrent ? "Current spoof · Look Around" : "Selected pin · Look Around")
            .toolbar { Button("Done") { dismiss() } }
            .task {
                repeat {
                    guard !Task.isCancelled else { return }
                    if phase == .active {
                        if let target {
                            let distance = requested.map { CLLocation(latitude: $0.latitude, longitude: $0.longitude).distance(from: CLLocation(latitude: target.latitude, longitude: target.longitude)) } ?? .infinity
                            if requested == nil || (followsCurrent && distance >= 15) { await load(target) }
                        } else {
                            scene = nil; loading = false
                            unavailable = "No active spoofed location. Start a location or route first."
                        }
                    }
                    if !followsCurrent { return }
                    do { try await Task.sleep(for: .seconds(3)) } catch { return }
                } while !Task.isCancelled
            }
        }
    }

    @MainActor private func load(_ coordinate: SelectedCoordinate) async {
        requested = coordinate
        loading = true
        let request = MKLookAroundSceneRequest(coordinate: coordinate.coreLocationCoordinate)
        defer { loading = false; request.cancel() }
        do {
            let result = try await request.scene
            guard !Task.isCancelled else { return }
            scene = result; sceneID = UUID()
            loaded = result == nil ? nil : coordinate
            unavailable = "Apple has no street-level imagery near these coordinates. Try another location."
        } catch {
            guard !Task.isCancelled else { return }
            scene = nil; loaded = nil
            requested = nil // Retry a temporary connection failure even while stationary.
            unavailable = "Imagery could not load. Check your connection and try again."
        }
    }
}
