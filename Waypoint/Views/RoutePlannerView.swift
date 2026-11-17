import MapKit
import SwiftUI
import UserNotifications

struct RoutePlannerView: View {
    @EnvironmentObject private var model: AppModel
    @State private var deviceTask: Task<Void, Never>?
    @State private var choosingWaitingLocation = false

    private enum WaitingLocation: String, Codable { case real, origin }

    private struct SavedRoute: Codable, Identifiable {
        var id = UUID()
        var origin: String
        var destination: String
        var mode: String
        var departure: Date
        var waitingLocation: WaitingLocation?
        var lastPoint: SelectedCoordinate?
        var speedOffset: Double?
        var customSpeed: Double?
        var pinned: Bool?
    }

    @AppStorage("interruptedRoute") private var interruptedData = Data()
    @AppStorage("recentRoutes") private var recentData = Data()
    @State private var previewFraction = 0.0
    @State private var paceReason = ""
    @State private var previewDetail = ""
    @State private var lastCheckpoint: Date?
    @State private var waitingUntil: Date?
    @State private var variants: [MKRoute] = []
    @State private var variantIndex = 0
    @State private var lastAccepted: Date?
    @State private var savedWaitingChoice: WaitingLocation?
    @State private var stopEnabled = false
    @State private var stopFraction = 0.5
    @State private var stopMinutes = 2
    @State private var clearHistory = false

    private func storeRecent(_ saved: SavedRoute) {
        let other = recents.filter { $0.id != saved.id }
        let pinned = other.filter { $0.pinned == true }
        let regular = other.filter { $0.pinned != true }
        let list = saved.pinned == true
            ? [saved] + pinned + Array(regular.prefix(8))
            : pinned + [saved] + Array(regular.prefix(7))
        recentData = (try? JSONEncoder().encode(list)) ?? Data()
    }
    private let showPreviewPoint: (CLLocationCoordinate2D?) -> Void

    private var interrupted: SavedRoute? { try? JSONDecoder().decode(SavedRoute.self, from: interruptedData) }
    private var recents: [SavedRoute] {
        (try? JSONDecoder().decode([SavedRoute].self, from: recentData)) ?? []
    }

    private func coordinates(_ position: SelectedCoordinate) -> String {
        "\(position.latitude), \(position.longitude)"
    }

    private func loadSaved(_ saved: SavedRoute, reverse: Bool = false, resume: Bool = false) {
        field = nil
        usesFixedOrigin = false
        locationOrigin = false
        startingPin = nil
        let start = resume ? saved.lastPoint.map(coordinates) ?? saved.origin : saved.origin
        origin = reverse ? saved.destination : start
        destination = reverse ? saved.origin : saved.destination
        locationOrigin = origin == "Current location"
        mode = TravelMode(rawValue: saved.mode) ?? .driving
        departure = reverse ? Date() : max(Date(), saved.departure)
        savedWaitingChoice = saved.waitingLocation
        speedOffset = saved.speedOffset ?? 0
        customPace = saved.customSpeed != nil
        speed = saved.customSpeed ?? 40
    }
    @StateObject private var search = PlaceSearchController()
    @FocusState private var field: Endpoint?
    @State private var region = MKCoordinateRegion(.world)
    @State private var deviceStatus: String?
    @State private var confirmedStart: Date?
    @State private var confirmedDuration = 0.0
    @State private var confirmedProgress = 0.0
    @State private var locationOrigin = false

    private enum Endpoint: Hashable { case origin, destination }
    private var searchQuery: String {
        switch field {
        case .origin: return origin
        case .destination: return destination
        case nil: return ""
        }
    }
    @State private var origin = ""
    @State private var usesFixedOrigin = false

    private let close: () -> Void

    private let showRoute: (MKPolyline?) -> Void

    init(defaultOrigin: SelectedCoordinate? = nil, defaultDestination: SelectedCoordinate, close: @escaping () -> Void, showPreviewPoint: @escaping (CLLocationCoordinate2D?) -> Void, showRoute: @escaping (MKPolyline?) -> Void) {
        self.close = close
        self.showRoute = showRoute
        self.showPreviewPoint = showPreviewPoint
        _region = State(initialValue: MKCoordinateRegion(center: defaultDestination.coreLocationCoordinate, latitudinalMeters: 30_000, longitudinalMeters: 30_000))
        _destination = State(initialValue: "\(defaultDestination.latitude), \(defaultDestination.longitude)")
        if let defaultOrigin {
            _origin = State(initialValue: "Active simulated location")
            _startingPin = State(initialValue: defaultOrigin.coreLocationCoordinate)
            _usesFixedOrigin = State(initialValue: true)
        }
    }
    @State private var destination = ""
    @State private var departure = Date()
    @State private var mode = TravelMode.driving
    @State private var playbackStart: Date?
    @State private var startingPin: CLLocationCoordinate2D?
    @State private var paused = false
    @State private var reversed = false
    @State private var arrived = false

    private enum TravelMode: String, CaseIterable, Identifiable {
        case driving = "Driving", walking = "Walking", cycling = "Cycling"
        var id: Self { self }
        var transport: MKDirectionsTransportType {
            switch self {
            case .driving: return .automobile
            case .walking: return .walking
            case .cycling: return .cycling
            }
        }
    }
    @State private var customPace = false
    @State private var speed = 40.0
    @State private var speedOffset = 0.0
    @State private var drivingRoad: DrivingRoad?
    @State private var livePace = 0.0
    @State private var route: MKRoute?
    @State private var isLoading = false
    @State private var errorMessage: String?

    private struct PreviewKey: Equatable {
        let origin: String
        let destination: String
        let mode: TravelMode
    }

    private var key: PreviewKey {
        PreviewKey(
            origin: origin.trimmingCharacters(in: .whitespacesAndNewlines),
            destination: destination.trimmingCharacters(in: .whitespacesAndNewlines),
            mode: mode
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            Button(action: close) {
                Label("Route planning", systemImage: "chevron.up")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.plain)
            .disabled(deviceTask != nil)
            Form {
            if deviceTask == nil, let saved = interrupted {
                Section("Interrupted route") {
                    Button("Prepare to resume") { loadSaved(saved, resume: true) }
                    if let point = saved.lastPoint {
                        Button("Hold last position") {
                            Task {
                                await model.startSimulation(at: point)
                                if model.simulatedCoordinate == point { interruptedData = Data() }
                            }
                        }
                    }
                    Button("Restore real location", role: .destructive) {
                        Task {
                            await model.stopSimulation()
                            if model.isReady { interruptedData = Data() }
                        }
                    }
                }
                .listRowBackground(Color.clear)
            }
            Section("Route") {
                TextField("Origin", text: $origin)
                    .focused($field, equals: .origin)
                    .disabled(locationOrigin || usesFixedOrigin)
                Button {
                    if usesFixedOrigin {
                        usesFixedOrigin = false
                        locationOrigin = false
                        origin = ""
                        startingPin = nil
                        field = .origin
                        return
                    }
                    locationOrigin.toggle()
                    origin = locationOrigin ? "Current location" : ""
                    startingPin = nil
                    field = nil
                } label: {
                    Label((locationOrigin || usesFixedOrigin) ? "Enter a different origin" : "Use current location", systemImage: "location")
                }
                TextField("Destination", text: $destination)
                    .focused($field, equals: .destination)
                if let endpoint = field {
                    ForEach(search.suggestions) { result in
                        Button {
                            let label = [result.title, result.subtitle].filter { !$0.isEmpty }.joined(separator: ", ")
                            if endpoint == .origin { origin = label; startingPin = nil }
                            else { destination = label }
                            field = nil
                        } label: {
                            VStack(alignment: .leading) {
                                Text(result.title)
                                Text(result.subtitle).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                Picker("Travel mode", selection: $mode) {
                    ForEach(TravelMode.allCases) { Text($0.rawValue).tag($0) }
                }
                Button(isLoading ? "Loading route…" : "Preview route") {
                    field = nil
                    let request = key
                    isLoading = true
                    Task { await preview(request) }
                }
                .disabled(isLoading || key.origin.isEmpty || key.destination.isEmpty)
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.secondary)
                }
            }
            .listRowBackground(Color.clear)
            Section("Schedule") {
                DatePicker("Departure", selection: $departure)
                if mode == .driving {
                    LabeledContent("Speed", value: "+\(Int(speedOffset)) km/h")
                    Slider(value: $speedOffset, in: 0...50, step: 1) { Text("Speed above posted limit") }
                        .disabled(deviceTask != nil)
                    Text("Offset above the posted limit. Missing limits use 40 km/h.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Toggle("Custom speed", isOn: $customPace)
                }
                if customPace && mode != .driving {
                    LabeledContent("Cruising target", value: "\(Int(speed)) km/h")
                        .monospacedDigit()
                    Slider(value: $speed, in: 1...250, step: 1) {
                        Text("Cruising target")
                    }
                    .disabled(deviceTask != nil)
                }
                Toggle("Timed stop on route", isOn: $stopEnabled)
                    .disabled(deviceTask != nil)
                if stopEnabled {
                    LabeledContent("Stop at", value: "\(Int(stopFraction * 100))% of planned time")
                    Slider(value: $stopFraction, in: 0.1...0.9, step: 0.05)
                        .accessibilityLabel("Stop position")
                        .disabled(deviceTask != nil)
                    Stepper("Wait \(stopMinutes) min", value: $stopMinutes, in: 1...60)
                        .disabled(deviceTask != nil)
                }
                if let route {
                    let estimate = confirmedStart == nil ? estimatedDuration(for: route) : confirmedDuration
                    LabeledContent("Suggested travel time", value: Duration.seconds(route.expectedTravelTime).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated)))
                    LabeledContent("Estimated arrival", value: departure.addingTimeInterval(estimate).formatted(date: .abbreviated, time: .shortened))
                }
            }
            .listRowBackground(Color.clear)
            Section {
                if let waitingUntil {
                    TimelineView(.periodic(from: .now, by: 1)) { clock in
                        if clock.date < waitingUntil {
                            Text("Departs in") + Text(" ") + Text(waitingUntil, style: .timer)
                        }
                    }
                }
                if !paceReason.isEmpty, confirmedStart != nil { Text(paceReason).font(.caption) }
                if let drivingRoad, mode == .driving, route != nil {
                    LabeledContent("Known speed limits", value: drivingRoad.knownLimitCoverage.formatted(.percent.precision(.fractionLength(0))))
                }
                if let lastAccepted {
                    LabeledContent("Last location update", value: lastAccepted.formatted(date: .omitted, time: .standard))
                }
                if deviceTask == nil, route != nil, deviceStatus == "Device updates stopped. Check the connection." {
                    Button("Retry from last confirmed point") {
                        if let saved = interrupted { loadSaved(saved, resume: true) }
                    }
                }
                if let deviceStatus {
                    Label(deviceStatus, systemImage: "location.circle").font(.headline)
                }
                if variants.count > 1, deviceTask == nil, !arrived {
                    Picker("Route alternative", selection: $variantIndex) {
                        ForEach(variants.indices, id: \.self) { index in
                            let option = variants[index]
                            Text("\(index + 1) · \(Int(option.distance / 1000)) km · \(Int(option.expectedTravelTime / 60)) min").tag(index)
                        }
                    }
                    .disabled(isLoading)
                    .onChange(of: variantIndex) { _, index in
                        guard variants.indices.contains(index) else { return }
                        let option = variants[index]
                        route = nil
                        isLoading = true
                        Task {
                            let road = mode == .driving ? await DrivingRoad.load(option.polyline) : nil
                            isLoading = false
                            guard variants.indices.contains(index), variants[index] === option else { return }
                            drivingRoad = road
                            route = option
                            showRoute(option.polyline)
                        }
                    }
                }
                if let route {
                    let duration = confirmedStart == nil
                        ? estimatedDuration(for: route)
                        : confirmedDuration
                    let arrival = (confirmedStart ?? max(Date(), departure)).addingTimeInterval(duration)
                    ProgressView(value: confirmedProgress).tint(.cyan)
                    if deviceTask == nil, !arrived {
                        if !previewDetail.isEmpty { Text(previewDetail).font(.caption) }
                        Slider(value: $previewFraction, in: 0...1) { Text("Preview route position") }
                            .onChange(of: previewFraction) { _, fraction in
                                let profile = drivingRoad?.profile(offset: speedOffset, reversed: reversed)
                                let index = Int(fraction * Double(max(0, route.polyline.pointCount - 1)))
                                let sample = profile?.position(at: fraction * duration)
                                if let sample {
                                    previewDetail = "\(Int(sample.1.rounded())) km/h · Road baseline \(Int(sample.2.rounded())) km/h"
                                }
                                let point = sample?.0
                                    ?? (route.polyline.pointCount > 0 ? route.polyline.points()[index].coordinate : nil)
                                showPreviewPoint(point)
                            }
                    }
                    HStack(spacing: 8) {
                        statistic("Remaining", String(format: "%.1f km", route.distance * (1 - confirmedProgress) / 1000))
                        statistic("Pace", paused || arrived || confirmedStart == nil ? "0 km/h" : "\(Int(livePace.rounded())) km/h")
                        statistic("Arrival", arrival.formatted(date: .omitted, time: .shortened))
                    }
                }
            }
            .listRowBackground(Color.clear)
            if !recents.isEmpty, deviceTask == nil {
                Section("Recent routes") {
                    Button("Clear recent routes", role: .destructive) { clearHistory = true }
                    ForEach(recents) { saved in
                        Menu(saved.destination) {
                            Button("Plan again") { loadSaved(saved) }
                            Button("Reverse endpoints") { loadSaved(saved, reverse: true) }
                            Button(saved.pinned == true ? "Unpin" : "Pin trip") {
                                var updated = saved
                                updated.pinned = saved.pinned != true
                                storeRecent(updated)
                            }
                        }
                    }
                }
                .listRowBackground(Color.clear)
            }
            }
            .scrollContentBackground(.hidden)
            if route != nil || deviceTask != nil {
                HStack {
                if deviceTask != nil, confirmedStart != nil {
                    Button(paused ? "Resume" : "Pause") { paused.toggle() }
                        .buttonStyle(.bordered)
                } else if arrived {
                    Button("Return via same route") {
                        reversed.toggle()
                        requestDeviceRoute()
                    }
                    .buttonStyle(.bordered)
                }
                Button {
                    if let deviceTask { deviceTask.cancel() }
                    else if arrived {
                        Task { await model.stopSimulation(); arrived = false }
                    } else { requestDeviceRoute() }
                } label: {
                    Text(deviceTask == nil && !arrived ? "Start \(mode.rawValue.lowercased())" : "Stop & Restore")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(deviceTask == nil ? .blue : .red)
                }
                .padding(12)
            }
        }
        .frame(height: 460)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28))
        .clipShape(RoundedRectangle(cornerRadius: 28))
        .padding(.horizontal, 8)
        .confirmationDialog("Clear recent routes?", isPresented: $clearHistory) {
            Button("Clear recent routes", role: .destructive) {
                recentData = (try? JSONEncoder().encode(recents.filter { $0.pinned == true })) ?? Data()
            }
        }
        .confirmationDialog("Until departure", isPresented: $choosingWaitingLocation, titleVisibility: .visible) {
            if let savedWaitingChoice {
                Button("Use saved waiting choice") { startDeviceRoute(waitingLocation: savedWaitingChoice) }
            }
            Button("Keep my real location") { startDeviceRoute(waitingLocation: .real) }
            Button("Hold the route origin") { startDeviceRoute(waitingLocation: .origin) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Choose the location your iPhone reports until the scheduled route starts.")
        }
        .onChange(of: searchQuery) { _, query in search.update(query: query, region: region) }
        .onDisappear {
            deviceTask?.cancel()
            showRoute(nil)
            showPreviewPoint(nil)
        }
        .onChange(of: key) { _, _ in
            deviceTask?.cancel()
            route = nil
            variants = []
            variantIndex = 0
            arrived = false
            reversed = false
            confirmedProgress = 0
            showRoute(nil)
            showPreviewPoint(nil)
            playbackStart = nil
            errorMessage = nil
        }
    }

    private func statistic(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.subheadline.bold()).monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func estimatedDuration(for route: MKRoute) -> Double {
        if mode == .driving, let drivingRoad {
            return drivingRoad.profile(offset: speedOffset, reversed: reversed).duration
        }
        return customPace ? route.distance / (speed / 3.6) : route.expectedTravelTime
    }

    private func requestDeviceRoute() {
        if departure > Date() {
            choosingWaitingLocation = true
        } else {
            startDeviceRoute()
        }
    }

    private func startDeviceRoute(waitingLocation: WaitingLocation? = nil) {
        guard let route else { return }
        let start = max(Date(), departure)
        let profile = mode == .driving ? drivingRoad?.profile(offset: speedOffset, reversed: reversed) : nil
        let duration = profile?.duration ?? (customPace ? route.distance / (speed / 3.6) : route.expectedTravelTime)
        guard duration.isFinite, duration > 0 else { return }
        arrived = false
        paused = false
        confirmedProgress = 0
        playbackStart = start
        deviceStatus = start > Date() ? "Waiting for departure" : "Connecting to device"
        let source = usesFixedOrigin ? startingPin.map { coordinates(SelectedCoordinate($0)) } ?? self.origin : self.origin
        let stopAt = stopEnabled ? duration * stopFraction : nil
        let stopDuration = Double(stopMinutes * 60)
        var saved = SavedRoute(origin: reversed ? destination : source, destination: reversed ? source : destination,
                               mode: mode.rawValue, departure: start, waitingLocation: waitingLocation,
                               speedOffset: speedOffset, customSpeed: customPace ? speed : nil)
        interruptedData = (try? JSONEncoder().encode(saved)) ?? Data()
        waitingUntil = start > Date() ? start : nil
        if let waitingUntil {
            Task {
                let center = UNUserNotificationCenter.current()
                guard (try? await center.requestAuthorization(options: [.alert, .sound])) == true,
                      self.waitingUntil == waitingUntil, waitingUntil.timeIntervalSinceNow > 0 else { return }
                let content = UNMutableNotificationContent()
                content.title = "Route departure"
                content.body = "Open Roam Control to check your route."
                let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, waitingUntil.timeIntervalSinceNow), repeats: false)
                try? await center.add(UNNotificationRequest(identifier: "route-departure", content: content, trigger: trigger))
            }
        }
        showPreviewPoint(nil)
        deviceTask = Task { @MainActor in
            var ownedSession: UUID?
            defer {
                confirmedStart = nil
                waitingUntil = nil
                UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["route-departure"])
                deviceTask = nil
                playbackStart = nil
            }
            do {
                guard let first = profile?.position(at: 0)?.0 ?? playbackCoordinate(at: start, duration: duration)
                else { return }
                let origin = SelectedCoordinate(first)
                saved.lastPoint = origin
                lastCheckpoint = nil
                if start > Date(), let waitingLocation {
                    switch waitingLocation {
                    case .real:
                        if model.simulationSessionID != nil {
                            await model.stopSimulation()
                            guard model.simulationSessionID == nil, model.isReady else {
                                deviceStatus = "Couldn’t confirm your real location. Check the connection."
                                return
                            }
                        }
                        deviceStatus = "Waiting for departure · real location"
                    case .origin:
                        deviceStatus = "Connecting to hold the origin"
                        if model.simulationSessionID == nil {
                            await model.startSimulation(at: origin)
                        }
                        guard let session = model.simulationSessionID else {
                            deviceStatus = "Couldn’t hold the origin. Check pairing in Settings."
                            return
                        }
                        ownedSession = session
                        if !Task.isCancelled {
                            let accepted = await model.updateRoutePosition(origin, session: session)
                            if !accepted {
                                if model.simulationSessionID == session {
                                    await model.stopSimulation()
                                }
                                deviceStatus = "Couldn’t hold the origin. Check the connection."
                                return
                            }
                            model.rememberSimulatedLocation(origin)
                            model.beginResendLoop(for: session)
                            deviceStatus = "Waiting for departure · holding origin"
                        }
                    }
                    try Task.checkCancellation()
                    try await Task.sleep(for: .seconds(max(0, start.timeIntervalSinceNow)))
                }
                try Task.checkCancellation()
                if let ownedSession, model.simulationSessionID != ownedSession {
                    deviceStatus = "Origin hold was interrupted. Start the route again."
                    return
                }
                deviceStatus = "Connecting to device"
                if model.simulationSessionID == nil {
                    await model.startSimulation(at: SelectedCoordinate(first))
                }
                guard let session = model.simulationSessionID else {
                    deviceStatus = "Couldn’t start the device route. Check pairing in Settings."
                    return
                }
                ownedSession = session
                let actualStart = Date()
                playbackStart = actualStart
                confirmedStart = actualStart
                confirmedDuration = duration
                confirmedProgress = 0
                deviceStatus = "Device session active"
                var elapsed = 0.0
                var stopRelease: ContinuousClock.Instant?
                var servedStop = false
                var lastTick = ContinuousClock.now
                while !Task.isCancelled && model.simulationSessionID == session {
                    let tick = ContinuousClock.now
                    let interval = (tick - lastTick).components
                    lastTick = tick
                    if !paused, stopRelease == nil { elapsed += Double(interval.seconds) + Double(interval.attoseconds) / 1e18 }
                    if let stopAt, elapsed >= stopAt, !servedStop {
                        elapsed = stopAt
                        stopRelease = tick.advanced(by: .seconds(stopDuration))
                        servedStop = true
                    }
                    if let release = stopRelease, tick >= release { stopRelease = nil }
                    deviceStatus = stopRelease != nil ? "Timed stop · holding location"
                        : (paused ? "Paused · holding location" : "Device session active")
                    let sample = profile?.position(at: elapsed)
                    guard let point = sample?.0 ?? playbackCoordinate(at: actualStart.addingTimeInterval(elapsed), duration: duration),
                          await model.updateRoutePosition(SelectedCoordinate(point), session: session)
                    else {
                        deviceStatus = "Device updates stopped. Check the connection."
                        break
                    }
                    lastAccepted = Date()
                    let nextPace = stopRelease != nil ? 0 : (sample?.1 ?? route.distance / duration * 3.6)
                    if paused { paceReason = "Holding position" }
                    else if nextPace < livePace - 0.1 { paceReason = "Braking" }
                    else if nextPace > livePace + 0.1 { paceReason = "Accelerating" }
                    else { paceReason = "Cruising" }
                    if let sample { paceReason += " · Road baseline \(Int(sample.2.rounded())) km/h" }
                    livePace = nextPace
                    if lastCheckpoint.map({ Date().timeIntervalSince($0) >= 5 }) ?? true {
                        saved.lastPoint = SelectedCoordinate(point)
                        interruptedData = (try? JSONEncoder().encode(saved)) ?? Data()
                        lastCheckpoint = Date()
                    }
                    confirmedProgress = min(1, elapsed / duration)
                    confirmedStart = Date().addingTimeInterval(-elapsed)
                    if confirmedProgress >= 1 {
                        deviceStatus = "Arrived · holding location"
                        arrived = true
                        storeRecent(saved)
                        interruptedData = Data()
                        model.rememberSimulatedLocation(SelectedCoordinate(point))
                        model.beginResendLoop(for: session)
                        return
                    }
                    try await Task.sleep(for: .milliseconds(100))
                }
            } catch {
                deviceStatus = "Route stopped"
            }
            if let ownedSession, model.simulationSessionID == ownedSession {
                await model.stopSimulation()
            }
            if Task.isCancelled { interruptedData = Data() }
        }
    }

    private func playbackCoordinate(at date: Date, duration scheduledDuration: Double? = nil) -> CLLocationCoordinate2D? {
        guard let route, let playbackStart, date >= playbackStart else { return nil }
        let duration = scheduledDuration ?? (customPace ? route.distance / (speed / 3.6) : route.expectedTravelTime)
        guard duration > 0, route.polyline.pointCount > 1 else { return nil }
        let progress = min(1, date.timeIntervalSince(playbackStart) / duration)
        let fraction = reversed ? 1 - progress : progress
        let points = route.polyline.points()
        let count = route.polyline.pointCount
        let length = (1..<count).reduce(0.0) { $0 + points[$1 - 1].distance(to: points[$1]) }
        var remaining = fraction * length
        for index in 1..<count {
            let first = points[index - 1]
            let last = points[index]
            let segment = first.distance(to: last)
            if segment > 0, remaining <= segment {
                let progress = remaining / segment
                return MKMapPoint(x: first.x + (last.x - first.x) * progress,
                                  y: first.y + (last.y - first.y) * progress).coordinate
            }
            remaining -= segment
        }
        return points[count - 1].coordinate
    }

    private func find(_ address: String) async throws -> MKMapItem {
        if address == "Active simulated location", let startingPin {
            return MKMapItem(placemark: MKPlacemark(coordinate: startingPin))
        }
        if address == "Current location" { return MKMapItem.forCurrentLocation() }
        let pieces = address.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        if pieces.count == 2, let lat = Double(pieces[0]), let lon = Double(pieces[1]) {
            let coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
            if CLLocationCoordinate2DIsValid(coordinate) {
                return MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
            }
        }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = address
        guard let result = try await MKLocalSearch(request: request).start().mapItems.first else {
            throw URLError(.resourceUnavailable)
        }
        return result
    }

    @MainActor
    private func preview(_ input: PreviewKey) async {
        defer { isLoading = false }
        errorMessage = nil
        do {
            async let start = find(input.origin)
            async let end = find(input.destination)
            let request = MKDirections.Request()
            request.source = try await start
            request.destination = try await end
            request.transportType = input.mode.transport
            request.requestsAlternateRoutes = true
            let options = try await MKDirections(request: request).calculate().routes
            guard let result = options.first else {
                throw URLError(.resourceUnavailable)
            }
            guard input == key else { return }
            let road = input.mode == .driving ? await DrivingRoad.load(result.polyline) : nil
            guard input == key else { return }
            drivingRoad = road
            variantIndex = 0
            variants = Array(options.prefix(3))
            route = result
            showRoute(result.polyline)
        } catch {
            guard input == key else { return }
            errorMessage = "Couldn’t load directions. Check the addresses and try again."
        }
    }
}
