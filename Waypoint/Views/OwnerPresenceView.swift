import SwiftUI
import MapKit

extension MemberProfile {
    var sharedCoordinate: CLLocationCoordinate2D? {
        guard share_location == true, let latitude, let longitude,
              CLLocationCoordinate2DIsValid(.init(latitude: latitude, longitude: longitude)) else { return nil }
        return .init(latitude: latitude, longitude: longitude)
    }
    var locationReportDate: Date? {
        guard let location_updated_at else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: location_updated_at) ?? ISO8601DateFormatter().date(from: location_updated_at)
    }
    var lastSeenDate: Date? {
        guard let last_seen else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: last_seen) ?? ISO8601DateFormatter().date(from: last_seen)
    }
    func appearsActive(at date: Date) -> Bool {
        is_active == true && lastSeenDate.map { date.timeIntervalSince($0) < 45 } == true
    }
}
struct ProfileAvatar: View {
    let photo: String?
    var size: CGFloat = 44
    var body: some View {
        Group {
            if let photo, let data = Data(base64Encoded: photo), let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFill()
            } else { Image(systemName: "person.crop.circle.fill").resizable().scaledToFit().foregroundStyle(.secondary) }
        }.frame(width: size, height: size).clipShape(Circle())
    }
}
struct MemberPresenceSummary: View {
    let member: MemberProfile
    var body: some View {
        TimelineView(.periodic(from: .now, by: 10)) { context in
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    ProfileAvatar(photo: member.profile_photo)
                    Text(member.username).font(.headline)
                    if member.appearsActive(at: context.date) { Circle().fill(.green).frame(width: 9, height: 9).accessibilityLabel("Active recently") }
                }
                if let last = member.lastSeenDate { Text("Last active: \(last.formatted(date: .abbreviated, time: .standard))").font(.caption) }
                else { Text("Last active: not reported yet").font(.caption) }
                if let point = member.sharedCoordinate {
                    Text(String(format: "%@ · %.6f, %.6f", member.is_spoofing == true ? "Spoofing" : "Device-reported location", point.latitude, point.longitude)).font(.caption).textSelection(.enabled)
                    if let stamp = member.location_updated_at { Text("Location last reported: \(stamp)").font(.caption2).foregroundStyle(.secondary) }
                } else { Text(member.share_location == true ? "Location unavailable" : "Location not shared").font(.caption).foregroundStyle(.secondary) }
            }
        }
    }
}
struct OwnerPresenceMap: View {
    @EnvironmentObject private var accounts: AccountStore
    @Environment(\.scenePhase) private var phase
    @Environment(\.dismiss) private var dismiss
    @State private var position: MapCameraPosition = .automatic
    @State private var focusedMember: UUID?
    var body: some View {
        NavigationStack {
            Map(position: $position, selection: $focusedMember) {
                ForEach(accounts.members.filter { $0.sharedCoordinate != nil }) { member in
                    if let point = member.sharedCoordinate {
                        Annotation(member.username, coordinate: point) {
                            VStack(spacing: 3) {
                                ProfileAvatar(photo: member.profile_photo, size: 36)
                                    .overlay(Circle().stroke(member.is_spoofing == true ? .orange : .blue, lineWidth: 3))
                                Text(member.username).font(.caption.weight(.semibold)).lineLimit(1).padding(3).background(.regularMaterial, in: Capsule())
                                Text(member.is_spoofing == true ? "Spoofing" : "Reported location").font(.caption2).padding(3).background(.regularMaterial, in: Capsule())
                            }
                        }.tag(member.id).annotationTitles(.hidden)
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                VStack(alignment: .leading, spacing: 8) {
                    if let focusedMember, let member = accounts.members.first(where: { $0.id == focusedMember }) { MemberPresenceSummary(member: member) }
                    Text("Opt-in locations · refreshes every 15 seconds while open. Pins show the last report, not guaranteed live GPS.").font(.caption).foregroundStyle(.secondary)
                    if accounts.members.allSatisfy({ $0.sharedCoordinate == nil }) { Text("No users are currently sharing a location.") }
                }.padding().frame(maxWidth: .infinity, alignment: .leading).background(.regularMaterial)
            }
            .navigationTitle("User map")
            .toolbar { Button("Done") { dismiss() }; Button("Fit all") { position = .automatic } }
            .task(id: phase) {
                guard phase == .active else { return }
                while !Task.isCancelled {
                    await accounts.loadMembers()
                    do { try await Task.sleep(for: .seconds(15)) } catch { return }
                }
            }
        }
    }
}
