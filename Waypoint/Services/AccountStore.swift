import Foundation
import Security

struct MemberProfile: Codable, Identifiable {
    let id: UUID
    let username: String
    let email: String
    let tiktok: String
    let instagram: String
    let is_owner: Bool
}
struct OwnerMessage: Codable, Identifiable {
    let id: UUID
    let body: String
    let created_at: String
}
private struct AccountSession: Codable {
    let access_token: String
    let refresh_token: String
}

@MainActor final class AccountStore: ObservableObject {
    @Published var profile: MemberProfile?
    @Published var members: [MemberProfile] = []
    @Published var messages: [OwnerMessage] = []
    @Published var busy = false
    @Published var notice = ""
    @Published var checked = false
    private var session: AccountSession?
    private var refreshing = false
    private var remember = true
    private let keychainService = "com.ayanshxkeel.roamcontrol.accounts"
    private var base: String { (Bundle.main.object(forInfoDictionaryKey: "AccountServerURL") as? String ?? "").trimmingCharacters(in: CharacterSet(charactersIn: "/")) }
    var configured: Bool { base.hasPrefix("https://") }
    private struct Reply: Decodable {
        var token: String?
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
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let response = response as? HTTPURLResponse else { throw failure("Could not reach the account server.") }
        guard (200..<300).contains(response.statusCode) else {
            let error = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            throw failure(error?["message"] as? String ?? "Account request failed (\(response.statusCode)).")
        }
        return try JSONDecoder().decode(Reply.self, from: data)
    }
    private func failure(_ text: String) -> NSError { NSError(domain: "Account", code: 1, userInfo: [NSLocalizedDescriptionKey: text]) }
    private func save() throws {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: keychainService, kSecAttrAccount as String: "session"]
        SecItemDelete(query as CFDictionary)
        if remember, let session {
            var item = query
            item[kSecValueData as String] = try JSONEncoder().encode(session)
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { throw failure("Could not securely save your login. Try signing in again.") }
        }
    }
    func restore() async {
        defer { checked = true }
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: keychainService, kSecAttrAccount as String: "session", kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data,
              let saved = try? JSONDecoder().decode(AccountSession.self, from: data) else { return }
        session = saved
        await refresh()
    }
    func authenticate(signUp: Bool, username: String, email: String, password: String, tiktok: String, instagram: String, stay: Bool, ownerPasswords: [String]? = nil) async {
        guard !busy else { return }
        busy = true; notice = ""
        defer { busy = false }
        do {
            remember = stay
            var body: [String: Any] = ["email": email.trimmingCharacters(in: .whitespacesAndNewlines), "password": password, "username": username, "tiktok": tiktok, "instagram": instagram]
            if let ownerPasswords { body["passwords"] = ownerPasswords }
            let reply = try await request(ownerPasswords != nil ? "owner-signin" : (signUp ? "signup" : "signin"), body: body, authenticated: false)
            guard let token = reply.token, let member = reply.profile else { throw failure("Could not sign in. Please try again.") }
            session = AccountSession(access_token: token, refresh_token: token)
            profile = member
            try save()
        } catch { notice = error.localizedDescription; profile = nil }
    }
    func refresh() async {
        guard !refreshing, let expectedSession = session else { return }
        refreshing = true
        defer { refreshing = false }
        do {
            let reply = try await request("status")
            guard session?.access_token == expectedSession.access_token else { return }
            guard let member = reply.profile else { throw failure("Your account is no longer available.") }
            profile = member; messages = reply.messages ?? []
        } catch { profile = nil; notice = error.localizedDescription }
    }
    func signOut() async {
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
                if page.count < 500 { break }
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
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return false }
        do { _ = try await request("message", body: ["id": member.id.uuidString, "body": body]); return true }
        catch { notice = error.localizedDescription; return false }
    }
}
