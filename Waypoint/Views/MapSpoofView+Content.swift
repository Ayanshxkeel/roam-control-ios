import MapKit
import SwiftUI

extension MapSpoofView {
    private var baseContent: some View {
        map.safeAreaInset(edge: .top, spacing: 0) {
            VStack(spacing: 7) {
                searchHeader
                if isSearchPresented {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) { searchSuggestions }
                            .padding(12)
                    }.frame(maxHeight: 220).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
                }
                mapModeButtons
                if communityMode && accounts.canUseCommunity && !communityPinStatusDismissed {
                    SwipeDismissBanner(onDismiss: { withAnimation { communityPinStatusDismissed = true } }) {
                        communityPinStatus
                    }
                }
                if communityMode {
                    if !communityBannerDismissed {
                        SwipeDismissBanner(onDismiss: { withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { communityBannerDismissed = true } }) {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Label("Community map", systemImage: "person.3.fill").font(.subheadline.bold())
                                    Spacer()
                                    Button { withAnimation { communityBannerDismissed = true } } label: { Image(systemName: "xmark") }.accessibilityLabel("Dismiss Community map notice")
                                }
                                if accounts.canUseCommunity {
                                    Text("Approximate areas · Switch to Regular map to hide people. Leave Community map in your profile to stop sharing.").font(.caption)
                                    if accounts.needsCommunityRetentionConsent {
                                        Button("Review last-known sharing") { communityMapPresented = true }
                                    }
                                } else {
                                    Text(accounts.profile?.community_blocked == true ? "Community access is currently unavailable. Regular map and all spoofing controls still work." : "Join to see other opted-in users. Regular map and all spoofing controls still work.").font(.caption)
                                    Button("Community map access") { communityMapPresented = true }
                                }
                            }.padding(12).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                        }
                    }
                    if let member = accounts.communityMembers.first(where: { $0.id == selectedCommunityMember }) {
                        HStack {
                            ProfileAvatar(photo: member.profile_photo, size: 36)
                            VStack(alignment: .leading) {
                                Text(member.username).font(.headline)
                                Text(member.is_spoofing == true ? "Simulated area · approximate" : "Device-reported area · approximate").font(.caption)
                                if let date = member.locationReportDate {
                                    Text("Last shared: \(date.formatted(date: .abbreviated, time: .standard))").font(.caption2).foregroundStyle(.secondary)
                                }
                                if !member.appearsActive(at: Date()) { Text("Last known · not updating live").font(.caption2).foregroundStyle(.secondary) }
                            }
                            Spacer()
                            Button { selectedCommunityMember = nil } label: { Image(systemName: "xmark") }.accessibilityLabel("Close community profile")
                        }.padding(10).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                    }
                }
                if let event = displayedEvent {
                    eventBanner(event)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                if let active = model.simulatedCoordinate, !activeBannerDismissed {
                    activeBanner(active)
                        .transition(.opacity)
                }
            }
            .padding(.top, 8)
            .padding(.horizontal)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if isRoutePlannerExpanded {
                RoutePlannerView(routeActivityChanged: { routeIsActive = $0 }, defaultOrigin: model.simulatedCoordinate, defaultDestination: selection, close: {
                    isRoutePlannerExpanded = false
                    routePreviewPoint = nil
                }, showPreviewPoint: { routePreviewPoint = $0 }, showRoute: { line in
                    plannedRouteLine = line
                    travelledRouteLine = nil
                    if let line { cameraPosition = .rect(line.boundingMapRect.insetBy(dx: -500, dy: -500)) }
                })
            } else {
                controls
            }
        }
        .toolbar(.hidden, for: .navigationBar)
         .sheet(isPresented: $communityMapPresented) {
            CommunityMapView(onAccessGranted: { communityMode = true; communityBannerDismissed = false; communityPinStatusDismissed = false; communityMapPresented = false })
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("RoamOpenCommunity"))) { _ in
            selectCommunityMap()
        }
        .onChange(of: accounts.communityMembers.map(\.id)) { _, _ in focusCommunityIfNeeded() }
        .onChange(of: accounts.canUseCommunity) { _, allowed in
            if !allowed { selectedCommunityMember = nil }
        }
        .task(id: "\(communityMode)-\(phase)-\(accounts.canUseCommunity)") {
            guard communityMode, phase == .active else { return }
            while !Task.isCancelled, communityMode, accounts.canUseCommunity {
                await accounts.loadCommunity()
                focusCommunityIfNeeded()
                do { try await Task.sleep(for: .seconds(15)) } catch { return }
            }
        }
        .sheet(isPresented: $mapOptionsPresented, onDismiss: applyMapAction) {
            MapOptionsView(mapAppearance: $mapAppearance, pinAppearance: $pinAppearance, drivingPOV: $drivingPOV,
                           canLookAroundCurrent: model.simulatedCoordinate != nil) { action in
                pendingMapAction = action
                mapOptionsPresented = false
            }.presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $lookAroundPresented) {
            PinLookAroundView(followsCurrent: lookAroundFollowsCurrent, selectedPin: lookAroundPin ?? selection).environmentObject(model)
        }
        .onChange(of: drivingPOV) { _, _ in lastCameraPoint = nil }
        .onChange(of: model.simulatedCoordinate) { _, point in
            if routeIsActive, Date().timeIntervalSince(lastTrailUpdate) >= 0.5, let point, let line = plannedRouteLine {
                lastTrailUpdate = Date()
                travelledRouteLine = RouteGeometry.covered(line, to: point.coreLocationCoordinate)
            }
            guard drivingPOV, !mapOptionsPresented, let point else { return }
            let next = point.coreLocationCoordinate
            let previous = lastCameraPoint ?? next
            if let last = lastCameraPoint,
               CLLocation(latitude: last.latitude, longitude: last.longitude).distance(from: CLLocation(latitude: next.latitude, longitude: next.longitude)) < 2 { return }
            lastCameraPoint = next
            let a = previous.latitude * .pi / 180, b = next.latitude * .pi / 180
            let d = (next.longitude - previous.longitude) * .pi / 180
            let heading = atan2(sin(d) * cos(b), cos(a) * sin(b) - sin(a) * cos(b) * cos(d)) * 180 / .pi
            cameraPosition = .camera(MapCamera(centerCoordinate: next, distance: 160, heading: heading, pitch: 65))
        }
        .sheet(isPresented: $model.isCellularStartPresented) {
            CellularStartView()
                .environmentObject(model)
        }
    }

    private func selectCommunityMap() {
        communityMode = true
        communityDidFrame = false
        communityBannerDismissed = false
        communityPinStatusDismissed = false
        if !accounts.canUseCommunity || accounts.needsCommunityRetentionConsent { communityMapPresented = true }
    }

    private var searchHeader: some View {
        HStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search a place or address", text: $searchText)
                    .focused($searchFocused).submitLabel(.search)
                    .autocorrectionDisabled()
                    .accessibilityLabel("Search a place or address")
                if !searchText.isEmpty {
                    Button { searchText = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }.accessibilityLabel("Clear search")
                }
                if isSearching { ProgressView().controlSize(.small) }
            }.padding(.horizontal, 12).frame(height: 44).background(.regularMaterial, in: Capsule())
            Button { searchFocused = false; model.isSetupPresented = true } label: {
                Image(systemName: model.isReady ? "checkmark.shield.fill" : "gearshape.fill")
                    .foregroundStyle(model.isReady ? .green : .primary)
                    .frame(width: 44, height: 44).background(.regularMaterial, in: Circle())
            }.accessibilityLabel("Settings")
        }
    }

    private var communityPinStatus: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                if accounts.communityLoading { ProgressView().controlSize(.small) }
                Text("\(accounts.communityMembers.count) shared pins").font(.caption.weight(.semibold))
                Spacer()
                Button("Refresh") { Task { await accounts.loadCommunity(); focusCommunityIfNeeded() } }.disabled(accounts.communityLoading)
                if !accounts.communityMembers.isEmpty { Button("Show pins") { fitCommunityPins() } }
            }
            if !accounts.communityError.isEmpty {
                Text(accounts.communityError).font(.caption2).foregroundStyle(.orange)
            } else if accounts.communityMembers.isEmpty && !accounts.communityLoading {
                Text("No shared locations yet. Other members must join and publish a location; allowing Community access alone does not create a pin.").font(.caption2).foregroundStyle(.secondary)
            }
            if accounts.profile?.is_owner == false, accounts.canShareLocation {
                Text(model.simulatedCoordinate == nil && sharingTracker.coordinate == nil ? sharingTracker.status : accounts.sharingStatus).font(.caption2).foregroundStyle(.secondary)
            }
        }.padding(10).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    private func focusCommunityIfNeeded() {
        guard communityMode, !communityDidFrame, !routeIsActive, !isRoutePlannerExpanded,
              !drivingPOV, !mapHasUserSelection, !isSearchPresented, !accounts.communityMembers.isEmpty else { return }
        fitCommunityPins()
    }

    private func fitCommunityPins() {
        let points = accounts.communityMembers.compactMap(\.sharedCoordinate)
        guard let first = points.first else { return }
        communityDidFrame = true
        drivingPOV = false
        withAnimation(.easeInOut(duration: 0.4)) {
            if points.count == 1 {
                cameraPosition = .region(MKCoordinateRegion(center: first, latitudinalMeters: 2500, longitudinalMeters: 2500))
            } else {
                let bounds = points.reduce(MKMapRect.null) { rect, point in
                    rect.union(MKMapRect(origin: MKMapPoint(point), size: MKMapSize(width: 1, height: 1)))
                }
                cameraPosition = .rect(bounds.insetBy(dx: -15000, dy: -15000))
            }
        }
    }

    private var mapModeButtons: some View {
        MapModeTabs(communitySelected: communityMode, selectRegular: {
            communityMode = false; selectedCommunityMember = nil
        }, selectCommunity: selectCommunityMap)
    }

    private func applyMapAction() {
        guard let action = pendingMapAction else { return }
        pendingMapAction = nil
        switch action {
        case .selectedLookAround:
            lookAroundFollowsCurrent = false; lookAroundPin = selection; lookAroundPresented = true
        case .currentLookAround:
            lookAroundFollowsCurrent = true; lookAroundPresented = true
        case .zoom:
            drivingPOV = false
            cameraPosition = .camera(MapCamera(centerCoordinate: selection.coreLocationCoordinate, distance: 180, heading: 0, pitch: 45))
        }
    }

    var searchAwareContent: some View {
        baseContent
        .onSubmit(of: .search) {
            searchSubmittedText()
        }
        .onChange(of: searchFocused) { _, focused in isSearchPresented = focused }
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
                searchFocused = false
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
            Map(position: $cameraPosition, interactionModes: .all, scope: mapControlScope) {
                communityAnnotations
                if let routePreviewPoint {
                    Marker("Route preview", coordinate: routePreviewPoint).tint(.orange)
                }
                if let plannedRouteLine {
                    MapPolyline(plannedRouteLine).stroke(.yellow, lineWidth: 6)
                    if let travelledRouteLine { MapPolyline(travelledRouteLine).stroke(.green, lineWidth: 7) }
                    if plannedRouteLine.pointCount > 0 {
                        Annotation("Starting point", coordinate: plannedRouteLine.points()[0].coordinate) {
                            PulsingMapPin(symbol: "flag.fill", color: .blue, pitch: mapPitch)
                        }
                    }
                }
                if let active = model.simulatedCoordinate,
                   active != selection {
                    Annotation("Active spoof", coordinate: active.coreLocationCoordinate) { PulsingMapPin(symbol: pinAppearance, color: .cyan, pitch: mapPitch) }
                }

                Annotation("Selected location", coordinate: selection.coreLocationCoordinate, anchor: .center) {
                    draggablePin(proxy: proxy)
                }
            }
            .mapStyle(mapAppearance == "Satellite" ? .imagery(elevation: .realistic) : (mapAppearance == "Hybrid" ? .hybrid(elevation: .realistic) : .standard(elevation: .realistic)))
            .mapControls {
                MapScaleView()
            }
            .coordinateSpace(name: "WaypointMap")
            .onTapGesture { point in
                if communityMode && accounts.canUseCommunity, accounts.communityMembers.contains(where: { member in
                    guard let coordinate = member.sharedCoordinate, let screen = proxy.convert(coordinate, to: .local) else { return false }
                    return abs(screen.x - point.x) < 65 && abs(screen.y - point.y) < 48
                }) { return }
                selectedCommunityMember = nil
                searchFocused = false
                guard pinDragOrigin == nil, Date().timeIntervalSince(lastPinDrag) > 0.3,
                      let coordinate = proxy.convert(point, from: .local) else { return }
                select(coordinate)
            }
            .onMapCameraChange(frequency: .onEnd) { context in
                mapPitch = context.camera.pitch
                visibleRegion = context.region
                placeSearch.update(region: context.region)
            }
            .overlay(alignment: .topTrailing) {
                ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 8) {
                    MapCompass(scope: mapControlScope)
                    MapPitchToggle(scope: mapControlScope)
                    Button {
                        if let spoof = model.simulatedCoordinate {
                            mapLocator.cancel(); zoomToCurrent(spoof)
                        } else { mapLocator.locate() }
                    } label: {
                        Group {
                            if mapLocator.locating { ProgressView() }
                            else { Image(systemName: "location.fill").font(.system(size: 19, weight: .semibold)).foregroundStyle(.cyan) }
                        }.frame(width: 44, height: 44).background(.regularMaterial, in: Circle())
                    }.buttonStyle(.plain)
                    .disabled(mapLocator.locating && model.simulatedCoordinate == nil)
                    .accessibilityLabel(model.simulatedCoordinate == nil ? "Zoom to my device location" : "Zoom to my spoofed location")
                    Button { mapOptionsPresented = true; drivingPOV = false; searchFocused = false } label: {
                        Image(systemName: "map.fill").font(.system(size: 18, weight: .semibold)).frame(width: 44, height: 44).background(.regularMaterial, in: Circle())
                    }.accessibilityLabel("Map controls")
                    Button { searchFocused = false; isRoutePlannerExpanded = true } label: {
                        Image(systemName: "point.topleft.down.to.point.bottomright.curvepath").font(.system(size: 18, weight: .semibold)).frame(width: 44, height: 44).background(.regularMaterial, in: Circle())
                    }.accessibilityLabel("Plan a route")
                    AccountMenu().environmentObject(accounts)

                }.padding(.vertical, 12).padding(.horizontal, 8)
                }.frame(width: 64).scrollBounceBehavior(.basedOnSize)
            }
        }
    }

    func zoomToCurrent(_ coordinate: SelectedCoordinate) {
        drivingPOV = false
        withAnimation(.easeInOut(duration: 0.4)) {
            cameraPosition = .camera(MapCamera(centerCoordinate: coordinate.coreLocationCoordinate, distance: 300, heading: 0, pitch: mapPitch))
        }
    }

    @MapContentBuilder private var communityAnnotations: some MapContent {
                if communityMode && accounts.canUseCommunity {
                    ForEach(accounts.communityMembers) { member in
                        if let point = member.sharedCoordinate {
                            Annotation(member.username, coordinate: point) {
                                Button { selectedCommunityMember = member.id } label: {
                                    VStack(spacing: 3) {
                                        ProfileAvatar(photo: member.profile_photo, size: 38)
                                            .overlay(Circle().stroke(member.is_spoofing == true ? .orange : .cyan, lineWidth: 3))
                                            .shadow(radius: 3)
                                        Text(member.username).font(.caption.weight(.semibold)).lineLimit(1)
                                            .padding(.horizontal, 5).padding(.vertical, 2).background(.regularMaterial, in: Capsule())
                                        if !member.appearsActive(at: Date()) { Text("Last known").font(.caption2).padding(2).background(.regularMaterial, in: Capsule()) }
                                    }.frame(maxWidth: 120)
                                }.buttonStyle(.plain).accessibilityLabel("Community member \(member.username), approximate area")
                            }.annotationTitles(.hidden)
                        }
                    }
                }

    }

    private var styledPin: some View {
        PulsingMapPin(symbol: pinAppearance, color: .red, pitch: mapPitch)
    }

    private func draggablePin(proxy: MapProxy) -> some View {
        styledPin
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 8, coordinateSpace: .named("WaypointMap"))
                .onChanged { value in
                    if pinDragOrigin == nil {
                        pinDragOrigin = proxy.convert(selection.coreLocationCoordinate, to: .local)
                    }
                    guard let origin = pinDragOrigin,
                          let coordinate = proxy.convert(CGPoint(x: origin.x + value.translation.width, y: origin.y + value.translation.height), from: .local) else { return }
                    lastPinDrag = Date()
                    select(coordinate)
                }
                .onEnded { _ in pinDragOrigin = nil; lastPinDrag = Date() }
        )
        .accessibilityLabel("Selected location pin")
        .accessibilityHint("Drag to choose a simulated location")
    }
}
