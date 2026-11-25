import MapKit
import SwiftUI

@MainActor
struct MapSpoofView: View {
    var openSupport: () -> Void
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var accounts: AccountStore
    @EnvironmentObject var sharingTracker: SharedLocationTracker
    @State var communityDidFrame = false
    @State var mapHasUserSelection = false
    @Environment(\.scenePhase) var phase
    @State var communityMode = true
    @State var communityBannerDismissed = false
    @State var communityPinStatusDismissed = false
    @FocusState var searchFocused: Bool
    @State var selectedCommunityMember: UUID?

    @ObservedObject var pathMonitor = CellularPathMonitor.shared
    @Namespace var mapControlScope
    @StateObject var mapLocator = MapLocationLocator()
    @StateObject var placeSearch = PlaceSearchController()
    @AppStorage("mapAppearance") var mapAppearance = "Standard"
    @AppStorage("pinAppearance") var pinAppearance = "mappin.circle.fill"
    @State var drivingPOV = false
    @State var lastCameraPoint: CLLocationCoordinate2D?
    @State var lookAroundPresented = false
    @State var lookAroundFollowsCurrent = false
    @State var lookAroundPin: SelectedCoordinate?
    @State var routeIsActive = false
    @State var mapOptionsPresented = false
    @State var communityMapPresented = false
    @State var mapPitch = 0.0
    @State var pendingMapAction: MapOptionsView.Action?
    @State var lastTrailUpdate = Date.distantPast
    @State var travelledRouteLine: MKPolyline?
    @State var pinDragOrigin: CGPoint?
    @State var lastPinDrag = Date.distantPast
    @State var activeBannerDismissed = false
    @State var selection: SelectedCoordinate
    @State var cameraPosition: MapCameraPosition
    @State var visibleRegion: MKCoordinateRegion
    @State var searchText = ""
    @State var isSearching = false
    @State var isRoutePlannerExpanded = false
    @State var plannedRouteLine: MKPolyline?
    @State var routePreviewPoint: CLLocationCoordinate2D?
    @AppStorage("favoritePinName") var favoritePinName = ""
    @AppStorage("favoritePin") var favoritePinData = Data()
    @State var isSearchPresented = false
    @State var searchTask: Task<Void, Never>?
    @State var searchOperationID: UUID?
    @State var displayedEvent: SimulationEvent?
    @State var eventDismissTask: Task<Void, Never>?
    @State var isCellularHandoffConfirmationPresented = false
    @State var isKeepaliveResumeConfirmationPresented = false

    private static let storedCoordinateKey = "selectedCoordinate"
    private static let defaultCoordinate = SelectedCoordinate(latitude: 48.8566, longitude: 2.3522)

    init(openSupport: @escaping () -> Void) {
        self.openSupport = openSupport
        let initial = Self.loadStoredCoordinate() ?? Self.defaultCoordinate
        let region = MKCoordinateRegion(
            center: initial.coreLocationCoordinate,
            latitudinalMeters: 6_000,
            longitudinalMeters: 6_000
        )

        _selection = State(initialValue: initial)
        _cameraPosition = State(initialValue: .region(region))
        _visibleRegion = State(initialValue: region)
    }

    var body: some View {
        searchAwareContent
            .task(id: selection) {
                do { try await Task.sleep(for: .milliseconds(250)); Self.store(selection) } catch { }
            }
            .onChange(of: model.simulationSessionID) { _, _ in activeBannerDismissed = false }
            .onReceive(mapLocator.$coordinate) { point in
                guard let point else { return }
                zoomToCurrent(model.simulatedCoordinate ?? point)
            }
            .onReceive(mapLocator.$message) { text in
                guard let text else { return }
                model.showError(title: "Location unavailable", error: NSError(domain: "MapLocation", code: 1, userInfo: [NSLocalizedDescriptionKey: text]))
            }
            .onChange(of: phase) { _, phase in if phase == .background { mapLocator.cancel() } }
            .onChange(of: model.simulationEvent) { _, event in
                show(event)
            }
            .onChange(of: model.isCellularHandoffInProgress) { _, isInProgress in
                guard isInProgress else { return }
                searchTask?.cancel()
                searchOperationID = nil
                isSearching = false
                isSearchPresented = false
                placeSearch.cancelAll()
                placeSearch.clearSuggestions()
            }
            .onChange(of: model.isCellularLaunchRunning) { _, isRunning in
                guard isRunning else { return }
                searchTask?.cancel()
                searchOperationID = nil
                isSearching = false
                isSearchPresented = false
                placeSearch.cancelAll()
                placeSearch.clearSuggestions()
            }
            .onDisappear {
                mapLocator.cancel()
                searchTask?.cancel()
                eventDismissTask?.cancel()
                placeSearch.cancelAll()
            }
    }

    private static func loadStoredCoordinate() -> SelectedCoordinate? {
        guard let data = UserDefaults.standard.data(forKey: storedCoordinateKey),
              let coordinate = try? JSONDecoder().decode(SelectedCoordinate.self, from: data),
              coordinate.isValid else {
            return nil
        }
        return coordinate
    }

    private static func store(_ coordinate: SelectedCoordinate) {
        guard let data = try? JSONEncoder().encode(coordinate) else { return }
        UserDefaults.standard.set(data, forKey: storedCoordinateKey)
    }
}
