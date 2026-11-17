import MapKit
import SwiftUI

extension MapSpoofView {
    private var baseContent: some View {
        ZStack(alignment: .top) {
            map
                .ignoresSafeArea(edges: .bottom)

            VStack(spacing: 9) {
                if let event = displayedEvent {
                    eventBanner(event)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                if let active = model.simulatedCoordinate {
                    activeBanner(active)
                        .transition(.opacity)
                }
            }
            .padding(.top, 8)
            .padding(.horizontal)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if isRoutePlannerExpanded {
                RoutePlannerView(defaultOrigin: model.simulatedCoordinate, defaultDestination: selection, close: {
                    isRoutePlannerExpanded = false
                    routePreviewPoint = nil
                }, showPreviewPoint: { routePreviewPoint = $0 }, showRoute: { line in
                    plannedRouteLine = line
                    if let line { cameraPosition = .rect(line.boundingMapRect.insetBy(dx: -500, dy: -500)) }
                })
            } else {
                controls
            }
        }
        .navigationTitle("Roam Control")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Support", action: openSupport)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isRoutePlannerExpanded = true
                } label: {
                    Label("Plan a route", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    model.isSetupPresented = true
                } label: {
                    Image(systemName: model.isReady ? "checkmark.shield.fill" : "gearshape.fill")
                        .foregroundStyle(model.isReady ? .green : .primary)
                }
                .accessibilityLabel("Settings")
            }
        }
        .sheet(isPresented: $model.isCellularStartPresented) {
            CellularStartView()
                .environmentObject(model)
        }
    }

    var searchAwareContent: some View {
        baseContent
        .searchable(
            text: $searchText,
            isPresented: $isSearchPresented,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Search a place or address"
        )
        .searchSuggestions {
            searchSuggestions
        }
        .onSubmit(of: .search) {
            searchSubmittedText()
        }
        .onChange(of: searchText) { _, query in
            guard isSearchPresented else { return }

            if isSearching {
                searchTask?.cancel()
                placeSearch.cancelAll()
                searchOperationID = nil
                isSearching = false
            }
            placeSearch.update(query: query, region: visibleRegion)
        }
        .onChange(of: isSearchPresented) { _, presented in
            if presented {
                placeSearch.update(query: searchText, region: visibleRegion)
            } else {
                placeSearch.clearSuggestions()
            }
        }
        .confirmationDialog(
            "Switch this spoof to cellular?",
            isPresented: $isCellularHandoffConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("Prepare cellular handoff") {
                model.armCellularHandoff()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("LocalDevVPN must still be connected, Airplane Mode must be ON, and Wi-Fi must be OFF. After tapping Prepare, wait until Waypoint says “Turn Airplane Mode off now”, then switch it off in Control Center while keeping Wi-Fi off.")
        }
        .confirmationDialog(
            "Resume location updates?",
            isPresented: $isKeepaliveResumeConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("Resume keepalive") {
                model.resumeSimulationAfterHandoffFailure()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Before resuming, enable Airplane Mode again with Wi-Fi off, or connect to a Wi-Fi network. Resuming while cellular is the only active interface can end the developer session.")
        }
    }

    private var searchSuggestions: some View {
        Group {
            if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               let favorite = try? JSONDecoder().decode(SelectedCoordinate.self, from: favoritePinData) {
                Button {
                    select(favorite.coreLocationCoordinate)
                    isSearchPresented = false
                } label: {
                    Label(favoritePinName.isEmpty ? "Favorite pin" : favoritePinName, systemImage: "star.fill")
                }
            }
            if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               let recent = model.lastSimulatedLocation {
                Button {
                    select(recent.coreLocationCoordinate)
                    isSearchPresented = false
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("Last simulated location", systemImage: "clock.arrow.circlepath")
                        Text(String(format: "%.5f, %.5f", recent.latitude, recent.longitude))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .disabled(model.isCellularHandoffInProgress)
            }
            if placeSearch.isCompleting && placeSearch.suggestions.isEmpty {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Finding places…")
                        .foregroundStyle(.secondary)
                }
            }

            ForEach(placeSearch.suggestions) { suggestion in
                Button {
                    selectSuggestion(suggestion)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "mappin.and.ellipse")
                            .foregroundStyle(.red)
                            .frame(width: 24)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(suggestion.title)
                                .foregroundStyle(.primary)

                            if !suggestion.subtitle.isEmpty {
                                Text(suggestion.subtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }

                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(model.isCellularHandoffInProgress)
            }

            if placeSearch.completionFailed,
               !searchText.isEmpty,
               placeSearch.suggestions.isEmpty {
                Label("Suggestions temporarily unavailable", systemImage: "wifi.exclamationmark")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var map: some View {
        MapReader { proxy in
            Map(position: $cameraPosition, interactionModes: .all) {
                if let routePreviewPoint {
                    Marker("Route preview", coordinate: routePreviewPoint).tint(.orange)
                }
                if let plannedRouteLine {
                    MapPolyline(plannedRouteLine).stroke(.cyan, lineWidth: 5)
                }
                if let active = model.simulatedCoordinate,
                   active != selection {
                    Marker("Active spoof", coordinate: active.coreLocationCoordinate)
                        .tint(.blue)
                }

                Annotation("Selected location", coordinate: selection.coreLocationCoordinate, anchor: .bottom) {
                    draggablePin(proxy: proxy)
                }
            }
            .mapStyle(.standard(elevation: .realistic))
            .mapControls {
                MapCompass()
                MapScaleView()
                MapPitchToggle()
            }
            .coordinateSpace(name: "WaypointMap")
            .onTapGesture { point in
                guard let coordinate = proxy.convert(point, from: .local) else { return }
                select(coordinate)
            }
            .onMapCameraChange(frequency: .onEnd) { context in
                visibleRegion = context.region
                placeSearch.update(region: context.region)
            }
        }
    }

    private func draggablePin(proxy: MapProxy) -> some View {
        ZStack {
            Circle()
                .fill(.white)
                .frame(width: 46, height: 46)
                .shadow(color: .black.opacity(0.22), radius: 7, y: 3)

            Image(systemName: "mappin.circle.fill")
                .font(.system(size: 36))
                .symbolRenderingMode(.palette)
                .foregroundStyle(.red, .white)
        }
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .named("WaypointMap"))
                .onChanged { value in
                    guard let coordinate = proxy.convert(value.location, from: .named("WaypointMap")) else { return }
                    select(coordinate)
                }
        )
        .accessibilityLabel("Selected location pin")
        .accessibilityHint("Drag to choose a simulated location")
    }
}
