import Foundation
import Combine
import Security

final class AccountProtocol: URLProtocol, @unchecked Sendable {
    static var mode = "login"
    static var delayedStarted = false
    static let accountID = UUID().uuidString
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        if Self.mode == "offline" {
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet)); return
        }
        let status = Self.mode == "revoked" ? 401 : (Self.mode == "server" ? 503 : 200)
        var mockMessages: [[String: String]] = []
        if Self.mode.hasPrefix("messages") {
            for index in 0..<(Self.mode == "messages-many" ? 3 : 1) {
                mockMessages.append(["id": "00000000-0000-4000-8000-00000000012\(index + 3)", "body": "Announcement \(index)", "created_at": "2026-11-24"])
            }
        }
        let payload: [String: Any] = status == 200 ? [
            "token": "test-session",
            "profile": ["id": Self.accountID, "username": "Test", "email": "test@example.com", "tiktok": "", "instagram": "", "is_owner": false, "share_location": false, "community_enabled": Self.mode == "community", "community_blocked": false],
            "messages": mockMessages
        ] : ["message": "Unavailable"]
        let body = String(data: try! JSONSerialization.data(withJSONObject: payload), encoding: .utf8)!
        if Self.mode == "delayed" {
            Self.delayedStarted = true
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.3) { [self] in
                client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: Data(body.utf8)); client?.urlProtocolDidFinishLoading(self)
            }
            return
        }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8)); client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
@main struct AccountOfflineTests {
    @MainActor static func main() async {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [AccountProtocol.self]
        let store = AccountStore(endpoint: "https://accounts.example.test", transport: URLSession(configuration: config), keychainService: "roam-tests-" + UUID().uuidString)
        await store.authenticate(signUp: false, username: "", email: "test@example.com", password: "test-password", tiktok: "", instagram: "", stay: false)
        precondition(store.profile != nil, "Login should succeed")
        AccountProtocol.mode = "messages"; await store.refresh(); await store.loadMessages()
        precondition(store.unreadMessages.count == 1 && store.pendingMessage != nil, "New messages need a badge and alert")
        store.dismissPendingAlerts()
        precondition(store.pendingMessage == nil && store.unreadMessages.count == 1, "Dismissing alert should retain badge")
        store.markMessagesRead()
        precondition(store.unreadMessages.isEmpty, "Reading clears badge")
        AccountProtocol.mode = "messages-many"; await store.loadMessages()
        precondition(store.unreadMessages.count == 2, "Badge must count two newly unread messages")
        store.dismissPendingAlerts()
        precondition(store.pendingMessage == nil && store.unreadMessages.count == 2, "Swiping alert must retain the numbered badge")
        await store.refresh()
        precondition(store.unreadMessages.count == 2, "Profile refresh must not mark the inbox read")
        precondition(!store.canUseCommunity, "Not joined by default")
        AccountProtocol.mode = "community"
        let joined = await store.updateCommunity(true)
        precondition(joined && store.canUseCommunity && store.canShareLocation)
        precondition(store.profile?.share_location == false, "Joining community must not enable private owner sharing")
        AccountProtocol.mode = "offline"
        let leftOffline = await store.updateCommunity(false)
        precondition(!leftOffline && !store.canUseCommunity && !store.canShareLocation, "Offline leave must stop local sharing and access immediately")
        AccountProtocol.mode = "offline"; await store.refresh()
        precondition(store.profile != nil, "Network loss must retain login")
        AccountProtocol.mode = "server"; await store.refresh()
        precondition(store.profile != nil, "Server outage must retain login")
        AccountProtocol.mode = "login"; await store.refresh()
        precondition(store.profile != nil && store.notice.isEmpty, "Reconnect must recover")
        AccountProtocol.mode = "revoked"; await store.refresh()
        precondition(store.profile == nil, "Server revocation must clear login")
        AccountProtocol.mode = "login"
        let service = "roam-persistence-test-" + UUID().uuidString
        let first = AccountStore(endpoint: "https://accounts.example.test", transport: URLSession(configuration: config), keychainService: service)
        await first.authenticate(signUp: false, username: "", email: "test@example.com", password: "test-password", tiktok: "", instagram: "", stay: true)
        precondition(first.profile != nil, "Persistent login should save")
        AccountProtocol.mode = "offline"
        let reopened = AccountStore(endpoint: "https://accounts.example.test", transport: URLSession(configuration: config), keychainService: service)
        await reopened.restore()
        precondition(reopened.checked && reopened.profile != nil, "Offline relaunch should restore the saved profile")
        AccountProtocol.mode = "login"
        await reopened.signOut()
        let signedOut = AccountStore(endpoint: "https://accounts.example.test", transport: URLSession(configuration: config), keychainService: service)
        await signedOut.restore()
        precondition(signedOut.profile == nil, "Explicit sign out clears persistence")
        AccountProtocol.mode = "login"
        let race = AccountStore(endpoint: "https://accounts.example.test", transport: URLSession(configuration: config), keychainService: "roam-race-" + UUID().uuidString)
        await race.authenticate(signUp: false, username: "", email: "test@example.com", password: "test-password", tiktok: "", instagram: "", stay: false)
        AccountProtocol.mode = "delayed"
        let pending = Task { await race.refresh() }
        for _ in 0..<100 {
            if AccountProtocol.delayedStarted { break }
            try? await Task.sleep(for: .milliseconds(5))
        }
        precondition(AccountProtocol.delayedStarted, "The stale refresh must be in flight")
        AccountProtocol.mode = "community"
        let accepted = await race.updateCommunity(true)
        precondition(accepted)
        await pending.value
        precondition(race.canUseCommunity, "A stale refresh must not undo accepted consent")
        print("PASS: accepted consent survives an older in-flight account response")
        print("PASS: persisted offline relaunch and explicit sign-out")
        print("PASS: offline preservation, server outage, reconnect, session revocation")
    }
}
