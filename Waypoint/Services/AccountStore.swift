import Foundation
import Security
import Combine

struct MemberProfile: Codable, Identifiable {
    let id: UUID
    let username: String
    let email: String
    let tiktok: String
    let instagram: String
    let is_owner: Bool
    var referral_source: String? = nil
    var referral_handle: String? = nil
    var profile_photo: String? = nil
    var share_location: Bool? = nil
    var community_enabled: Bool? = nil
    var community_blocked: Bool? = nil
    var community_keep_for_owner: Bool? = nil
    var last_seen: String? = nil
    var is_active: Bool? = nil
    var latitude: Double? = nil
    var longitude: Double? = nil
    var is_spoofing: Bool? = nil
    var location_updated_at: String? = nil
}
struct OwnerMessage: Codable, Identifiable {
    let id: UUID
    let body: String
    let created_at: String
}
private struct AccountSession: Codable {
    let access_token: String
    let refresh_token: String
    var cachedProfile: MemberProfile? = nil
    var cachedMessages: [OwnerMessage]? = nil
}

@MainActor final class AccountStore: ObservableObject {
    @Published var locationSharingPaused = false
    @Published var communitySharingPaused = false
    var communityRequested = false
    func openRequestedCommunity() {
        guard communityRequested else { return }
        communityRequested = false
        NotificationCenter.default.post(name: Notification.Name("RoamOpenCommunity"), object: nil)
    }
    @Published var communityMembers: [MemberProfile] = []
    var needsCommunityRetentionConsent: Bool { profile?.is_owner == false && profile?.community_keep_for_owner != true }
    var canUseCommunity: Bool { profile?.is_owner == true || (profile?.community_enabled == true && profile?.community_blocked != true && !communitySharingPaused) }
    var canShareLocation: Bool {
        (profile?.share_location == true && !locationSharingPaused) || (profile?.community_enabled == true && profile?.community_blocked != true && !communitySharingPaused)
    }
    @Published var profile: MemberProfile?
    @Published var members: [MemberProfile] = []
    @Published var messages: [OwnerMessage] = []
    @Published var inboxLoading = false
    @Published var inboxError = ""
    @Published private var readMessageIDs: Set<UUID> = []
    @Published private var dismissedMessageIDs: Set<UUID> = []
    var unreadMessages: [OwnerMessage] { messages.filter { !readMessageIDs.contains($0.id) } }
    var pendingMessage: OwnerMessage? { unreadMessages.first { !dismissedMessageIDs.contains($0.id) } }
    func dismissMessage(_ id: UUID) { dismissedMessageIDs.insert(id) }
    func dismissPendingAlerts() { dismissedMessageIDs.formUnion(messages.map(\.id)) }
    private func loadReadState() {
        guard let id = profile?.id else { return }
        communitySharingPaused = UserDefaults.standard.bool(forKey: "communityPrivacyOff.\(id)")
        locationSharingPaused = UserDefaults.standard.bool(forKey: "locationPrivacyOff.\(id)")
        readMessageIDs = Set((UserDefaults.standard.stringArray(forKey: "readMessages.\(id)") ?? []).compactMap(UUID.init(uuidString:)))
    }
    func markMessagesRead() {
        guard let id = profile?.id else { return }
        readMessageIDs.formUnion(messages.map(\.id))
        UserDefaults.standard.set(readMessageIDs.map(\.uuidString), forKey: "readMessages.\(id)")
    }
    @Published var busy = false
    @Published var notice = ""
    @Published var checked = false
    private var session: AccountSession?
    private var refreshing = false
    private var profileRevision = 0
    @Published var presenceRequestID = UUID()
    @Published var communityLoading = false
    @Published var communityError = ""
    @Published var sharingStatus = "Waiting for a location report"
    private var remember = true
    private let keychainService: String
    private let transport: URLSession
    private let endpoint: String?
    init(endpoint: String? = nil, transport: URLSession = .shared, keychainService: String = "com.ayanshxkeel.roamcontrol.accounts") {
        self.keychainService = keychainService
        self.endpoint = endpoint; self.transport = transport
    }
    private var base: String { endpoint ??  (Bundle.main.object(forInfoDictionaryKey: "AccountServerURL") as? String ?? "").trimmingCharacters(in: CharacterSet(charactersIn: "/")) }
    var configured: Bool { base.hasPrefix("https://") }
    private struct Reply: Decodable {
        var token: String?
        var sent_count: Int?
        var profile: MemberProfile?
        var members: [MemberProfile]?
        var messages: [OwnerMessage]?
    }
    private func request(_ action: String, body: [String: Any] = [:], authenticated: Bool = true) async throws -> Reply {
        guard configured, let url = URL(string: base) else { throw failure("Online accounts are awaiting server setup.") }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 25
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if authenticated, let session { req.setValue("Bearer " + session.access_token, forHTTPHeaderField: "Authorization") }
        var payload = body
        payload["action"] = action
        req.httpBody = try JSONSerialization.data(withJSONObject: payload)
        let (data, response) = try await transport.data(for: req)
        guard let response = response as? HTTPURLResponse else { throw failure("Could not reach the account server.") }
        guard (200..<300).contains(response.statusCode) else {
            let error = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            throw NSError(domain: "AccountHTTP", code: response.statusCode, userInfo: [NSLocalizedDescriptionKey: error?["message"] as? String ?? "Account request failed (\(response.statusCode))."])
        }
        return try JSONDecoder().decode(Reply.self, from: data)
    }
    private func failure(_ text: String) -> NSError { NSError(domain: "Account", code: 1, userInfo: [NSLocalizedDescriptionKey: text]) }
    private func save() throws {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: keychainService, kSecAttrAccount as String: "session"]
        guard remember, let session else { SecItemDelete(query as CFDictionary); return }
        let data = try JSONEncoder().encode(session)
        let attributes: [String: Any] = [kSecValueData as String: data, kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            attributes.forEach { item[$0.key] = $0.value }
            guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { throw failure("Could not securely save your login.") }
        } else if status != errSecSuccess { throw failure("Could not securely update your login.") }
    }

    func restore() async {
        defer { checked = true }
        guard session == nil else { return }
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: keychainService, kSecAttrAccount as String: "session", kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data,
              let saved = try? JSONDecoder().decode(AccountSession.self, from: data) else { return }
        session = saved
        profile = saved.cachedProfile
        messages = saved.cachedMessages ?? []
        loadReadState()
        if profile != nil { checked = true }
        await refresh()
    }
    func authenticate(signUp: Bool, username: String, email: String, password: String, tiktok: String, instagram: String, stay: Bool, ownerPasswords: [String]? = nil, referralSource: String = "", referralHandle: String = "", profilePhoto: String = "", shareLocation: Bool = false) async {
        guard !busy else { return }
        busy = true; notice = ""
        defer { busy = false }
        do {
            remember = stay
            var body: [String: Any] = ["email": email.trimmingCharacters(in: .whitespacesAndNewlines), "password": password, "username": username, "tiktok": tiktok, "instagram": instagram]
            body["referral_source"] = referralSource
            body["referral_handle"] = referralHandle
            body["profile_photo"] = profilePhoto
            body["share_location"] = shareLocation
            if let ownerPasswords { body["passwords"] = ownerPasswords }
            let reply = try await request(ownerPasswords != nil ? "owner-signin" : (signUp ? "signup" : "signin"), body: body, authenticated: false)
            guard let token = reply.token, let member = reply.profile else { throw failure("Could not sign in. Please try again.") }
            session = AccountSession(access_token: token, refresh_token: token, cachedProfile: member)
            profile = member
            loadReadState()
            dismissedMessageIDs = []
            try save()
        } catch { notice = error.localizedDescription; profile = nil }
    }
    func refresh() async {
        guard !refreshing, let expectedSession = session else { return }
        let revision = profileRevision
        refreshing = true
        defer { refreshing = false }
        do {
            if locationSharingPaused, profile?.share_location == true {
                _ = try await request("profile-settings", body: ["share_location": false])
            }
            if communitySharingPaused, profile?.community_enabled == true {
                _ = try await request("community-settings", body: ["enabled": false])
            }
            let reply = try await request("status")
            guard session?.access_token == expectedSession.access_token, revision == profileRevision else { return }
            guard let member = reply.profile else { throw failure("Your account is no longer available.") }
            profile = member
            loadReadState()
            session?.cachedProfile = member
            session?.cachedMessages = Array(messages.prefix(50))
            try save()
            notice = ""
        } catch {
            guard session?.access_token == expectedSession.access_token, revision == profileRevision else { return }
            let error = error as NSError
            if error.domain == "AccountHTTP", error.code == 401 || error.code == 403 {
                session = nil; profile = nil; messages = []; members = []; try? save()
                notice = error.localizedDescription
            } else {
                notice = "Offline or server unavailable. Your saved login is retained; account updates will retry when connected."
            }
        }
    }
    func signOut() async {
        await presence(active: false, spoof: nil, reported: nil)
        if session != nil { _ = try? await request("signout") }
        session = nil; profile = nil; members = []; messages = []; try? save()
    }
    func loadMembers() async {
        guard profile?.is_owner == true else { return }
        do {
            var all: [MemberProfile] = []
            while true {
                let page = try await request("list", body: ["offset": all.count]).members ?? []
                all.append(contentsOf: page)
                if page.count < 40 { break }
            }
            members = all
        } catch { notice = error.localizedDescription }
    }
    func deleteMember(_ member: MemberProfile) async {
        busy = true; defer { busy = false }
        do { _ = try await request("delete", body: ["id": member.id.uuidString]); await loadMembers() }
        catch { notice = error.localizedDescription }
    }
    func send(_ text: String, to member: MemberProfile) async -> Bool {
        guard !busy else { return false }
        busy = true; notice = ""
        defer { busy = false }
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return false }
        do { _ = try await request("message", body: ["id": member.id.uuidString, "body": body]); notice = "Message saved to \(member.username)’s inbox."; return true }
        catch { notice = error.localizedDescription; return false }
    }
    func broadcast(_ text: String, requestID: UUID) async -> Bool {
        guard profile?.is_owner == true, !busy else { return false }
        busy = true; notice = ""
        defer { busy = false }
        do {
            let result = try await request("broadcast", body: ["body": text, "request_id": requestID.uuidString])
            notice = "Notification sent to \(result.sent_count ?? 0) users’ inboxes."
            return true
        } catch { notice = error.localizedDescription; return false }
    }

    func presence(active: Bool, spoof: SelectedCoordinate?, reported: SelectedCoordinate?) async {
        guard let current = profile, !current.is_owner else { return }
        let revision = profileRevision
        var body: [String: Any] = ["active": active]
        if active, canShareLocation, let point = spoof ?? reported, point.isValid {
            body["latitude"] = point.latitude; body["longitude"] = point.longitude
            body["spoofing"] = spoof != nil
        }
        do {
            let result = try await request("presence", body: body)
            if profile?.id == current.id, revision == profileRevision, let updated = result.profile {
                profile = updated; session?.cachedProfile = updated
                if active && canShareLocation {
                    sharingStatus = body["latitude"] == nil ? "Waiting for device location or an active spoof" : "Location report uploaded"
                }
            }
        } catch { sharingStatus = "Could not upload location: " + error.localizedDescription }
    }
    func updateSharing(_ enabled: Bool) async {
        profileRevision += 1
        if !enabled, let id = profile?.id {
            locationSharingPaused = true
            UserDefaults.standard.set(true, forKey: "locationPrivacyOff.\(id)")
        }
        busy = true; defer { busy = false }
        do {
            let result = try await request("profile-settings", body: ["share_location": enabled])
            if let updated = result.profile {
                profile = updated; session?.cachedProfile = updated
                if enabled { locationSharingPaused = false; UserDefaults.standard.removeObject(forKey: "locationPrivacyOff.\(updated.id)") }
                try save()
            }
        } catch { notice = error.localizedDescription }
    }

    func updateCommunity(_ enabled: Bool) async -> Bool {
        profileRevision += 1
        if !enabled, let id = profile?.id {
            communitySharingPaused = true; communityMembers = []
            UserDefaults.standard.set(true, forKey: "communityPrivacyOff.\(id)")
        }
        busy = true; notice = ""
        defer { busy = false }
        do {
            let result = try await request("community-settings", body: ["enabled": enabled, "keep_for_owner": enabled])
            if let member = result.profile {
                profile = member; session?.cachedProfile = member
                if enabled { communitySharingPaused = false; UserDefaults.standard.removeObject(forKey: "communityPrivacyOff.\(member.id)") }
                try save()
                presenceRequestID = UUID()
            }
            return true
        } catch { notice = error.localizedDescription; return false }
    }
    func loadCommunity() async {
        guard !communityLoading else { return }
        guard canUseCommunity else { communityMembers = []; return }
        communityLoading = true
        defer { communityLoading = false }
        do {
            var all: [MemberProfile] = []
            while true {
                let page = try await request("community-list", body: ["offset": all.count]).members ?? []
                all += page
                if page.count < 40 { break }
            }
            guard canUseCommunity else { return }
            communityMembers = all
            communityError = ""
        } catch {
            communityMembers = []; communityError = error.localizedDescription; notice = error.localizedDescription
            if (error as NSError).code == 403 { await refresh() }
        }
    }
    func removeFromCommunity(_ member: MemberProfile, blocked: Bool) async {
        busy = true; defer { busy = false }
        do {
            _ = try await request("community-remove", body: ["id": member.id.uuidString, "blocked": blocked])
            await loadMembers()
        } catch { notice = error.localizedDescription }
    }

    func loadMessages() async {
        guard !inboxLoading, let expectedSession = session else { return }
        inboxLoading = true
        defer { inboxLoading = false }
        do {
            var all: [OwnerMessage] = []
            var offset = 0
            while !Task.isCancelled {
                let page = try await request("inbox", body: ["offset": offset]).messages ?? []
                all += page; offset += page.count
                if page.count < 100 { break }
            }
            guard !Task.isCancelled, session?.access_token == expectedSession.access_token else { return }
            var ids = Set<UUID>()
            messages = all.filter { ids.insert($0.id).inserted }
            session?.cachedMessages = Array(messages.prefix(50))
            try save()
            inboxError = ""
        } catch {
            guard session?.access_token == expectedSession.access_token, !Task.isCancelled else { return }
            inboxError = "Could not refresh messages: " + error.localizedDescription
        }
    }

}
