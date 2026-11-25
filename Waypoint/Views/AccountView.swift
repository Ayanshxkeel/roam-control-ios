import SwiftUI
import PhotosUI

struct AccountGate: View {
    @EnvironmentObject private var model: AppModel
    @StateObject private var tracker = SharedLocationTracker()
    @StateObject private var accounts = AccountStore()
    @Environment(\.scenePhase) private var phase
    @State private var showUpdates = true
    @State private var showingInbox = false
    @State private var lastLocationPublish = Date.distantPast
    var body: some View {
        Group {
            if !accounts.checked { ProgressView("Checking your account…") }
            else if accounts.profile != nil {
                RootView().environmentObject(accounts).environmentObject(tracker)
            } else { SignInView().environmentObject(accounts) }
        }
        .overlay(alignment: .top) {
            if !showUpdates, !showingInbox, phase == .active, accounts.profile != nil {
                MessageArrivalBanner(openInbox: { showingInbox = true }).environmentObject(accounts)
            }
        }
        .sheet(isPresented: $showingInbox) { MessageInboxView().environmentObject(accounts) }
        .fullScreenCover(isPresented: $showUpdates) { SocialUpdatesView { showUpdates = false } }
        .onChange(of: phase) { previous, next in
            if previous == .background && next == .active { showUpdates = true }
        }
        .task { await accounts.restore() }
        .task(id: "inbox-\(phase)-\(accounts.profile?.id.uuidString ?? "signed-out")") {
            guard phase == .active, accounts.profile != nil else { return }
            while !Task.isCancelled, accounts.profile != nil {
                await accounts.loadMessages()
                do { try await Task.sleep(for: .seconds(10)) } catch { return }
            }
        }
        .onChange(of: accounts.canShareLocation) { _, allowed in tracker.setEnabled(allowed && phase == .active) }
        .onReceive(tracker.$coordinate) { point in
            guard let point, phase == .active, accounts.canShareLocation, model.simulatedCoordinate == nil,
                  Date().timeIntervalSince(lastLocationPublish) > 5 else { return }
            lastLocationPublish = Date()
            Task {
                await accounts.presence(active: true, spoof: nil, reported: point)
                if accounts.canUseCommunity, !accounts.communityMembers.contains(where: { $0.id == accounts.profile?.id }) {
                    await accounts.loadCommunity()
                }
            }
        }
        .task(id: "\(phase)-\(accounts.presenceRequestID)") {
            tracker.setEnabled(accounts.canShareLocation && phase == .active)
            guard phase == .active else {
                await accounts.presence(active: false, spoof: nil, reported: nil)
                return
            }
            while !Task.isCancelled {
                await accounts.refresh()
                guard phase == .active, !Task.isCancelled else { tracker.setEnabled(false); return }
                tracker.setEnabled(accounts.canShareLocation)
                await accounts.presence(active: true, spoof: model.simulatedCoordinate, reported: tracker.coordinate)
                if accounts.canUseCommunity, accounts.communityMembers.isEmpty { await accounts.loadCommunity() }
                do { try await Task.sleep(for: .seconds(15)) } catch { return }
            }
        }
    }
}
private struct SignInView: View {
    @EnvironmentObject var accounts: AccountStore
    @State private var creating = false
    @State private var ownerLogin = false
    @State private var password2 = ""
    @State private var password3 = ""
    @State private var username = ""
    @State private var email = ""
    @State private var password = ""
    @State private var referralSource = ""
    @State private var referralHandle = ""
    @State private var stay = true
    @State private var photoItem: PhotosPickerItem?
    @State private var profilePhoto = ""
    @State private var photoError = ""
    @State private var shareLocation = false
    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(colors: [.cyan.opacity(0.22), .blue.opacity(0.1), .clear], startPoint: .topLeading, endPoint: .bottomTrailing).ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        Image(systemName: "location.north.circle.fill").font(.system(size: 64)).foregroundStyle(.cyan)
                        Text("Roam Control").font(.largeTitle.bold())
                        Text(creating ? "Create your account" : "Welcome back").font(.title2.bold())
                        Picker("Account", selection: $creating) { Text("Sign in").tag(false); Text("Sign up").tag(true) }.pickerStyle(.segmented).disabled(ownerLogin)
                        VStack(spacing: 16) {
                            if creating && !ownerLogin {
                                TextField("Username", text: $username).textContentType(.username)
                                PhotosPicker(selection: $photoItem, matching: .images) {
                                    HStack { ProfileAvatar(photo: profilePhoto); Text("Choose profile photo") }
                                }
                                if !photoError.isEmpty { Text(photoError).font(.caption).foregroundStyle(.orange) }
                            }
                            TextField("Email", text: $email).keyboardType(.emailAddress).textContentType(.emailAddress)
                            PasswordEntry(title: "Password", text: $password, creating: creating)
                            if ownerLogin {
                                PasswordEntry(title: "Owner password 2", text: $password2)
                                PasswordEntry(title: "Owner password 3", text: $password3)
                            }
                            if creating && !ownerLogin {
                                Picker("How did you hear about this app?", selection: $referralSource) {
                                    Text("Choose one").tag("")
                                    ForEach(["TikTok", "Instagram", "LinkedIn", "Resume"], id: \.self) { Text($0).tag($0) }
                                }.pickerStyle(.menu)
                                if !referralSource.isEmpty {
                                    TextField(referralSource == "Resume" ? "Your social @ or LinkedIn handle" : "Your \(referralSource) @ / handle", text: $referralHandle)
                                        .onChange(of: referralSource) { _, _ in referralHandle = "" }
                                    if referralSource == "Resume" {
                                        Text("Enter your TikTok, Instagram, or LinkedIn handle so the builder can identify your account.").font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }.textFieldStyle(.roundedBorder).textInputAutocapitalization(.never).autocorrectionDisabled()
                        Toggle("Owner sign-in", isOn: $ownerLogin).onChange(of: ownerLogin) { _, value in if value { creating = false } }
                        Toggle("Stay logged in", isOn: $stay)
                        if creating {
                            Toggle("Share my location with the builder", isOn: $shareLocation)
                            Text("Optional. When enabled, the owner can see your spoofed coordinates and spoofing status, or your device-reported location when not spoofing, while this app is open. Location pins may remain as the last report until replaced or sharing is turned off. You can change this in your profile. All accounts show recent activity and last-active time to the owner. Photos and social handles are also visible to the owner.").font(.footnote).foregroundStyle(.secondary)
                            Text("Account details are stored online. The owner can see your username, email and social handles, delete your account, and send you messages. Passwords are never visible to the owner.").font(.footnote).foregroundStyle(.secondary)
                            Text("Failing to follow @ayanshxkeel on TikTok may result in removal of your account. Follow status is not automatically verified.").font(.footnote)
                            Link("Follow @ayanshxkeel", destination: URL(string: "https://www.tiktok.com/@ayanshxkeel")!)
                        }
                if !accounts.notice.isEmpty { Text(accounts.notice).foregroundStyle(.orange).accessibilityLabel(accounts.notice) }
                        if !accounts.configured { Text("Online accounts are awaiting server setup.").font(.footnote).foregroundStyle(.secondary) }
                        Button {
                            Task {
                                await accounts.authenticate(signUp: creating, username: username, email: email, password: password, tiktok: "", instagram: "", stay: stay, ownerPasswords: ownerLogin ? [password, password2, password3] : nil, referralSource: referralSource, referralHandle: referralHandle, profilePhoto: profilePhoto, shareLocation: shareLocation)
                                password = ""; password2 = ""; password3 = ""
                            }
                        } label: {
                            HStack { Spacer(); if accounts.busy { ProgressView() }; Text(ownerLogin ? "Owner sign-in" : (creating ? "Create account" : "Sign in")); Spacer() }.padding(8)
                        }.buttonStyle(.borderedProminent)
                            .disabled(accounts.busy || (ownerLogin && (password2.isEmpty || password3.isEmpty)) || !accounts.configured || email.isEmpty || password.isEmpty || (creating && (referralSource.isEmpty || referralHandle.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "@", with: "").isEmpty || username.trimmingCharacters(in: .whitespaces).isEmpty || password.count < 8)))
                        if creating { Text("Use at least 8 characters for your password. Your account is available immediately after sign-up.").font(.caption).foregroundStyle(.secondary) }
                    }.padding(28).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 30)).padding()
                }
            }
        }
        .onChange(of: photoItem) { _, item in
            Task {
                do {
                    guard let data = try await item?.loadTransferable(type: Data.self) else { return }
                    profilePhoto = try ProfilePhotoEncoder.encode(data)
                    photoError = ""
                } catch { photoError = "Could not load that photo. Choose another image." }
            }
        }
    }
}
struct AccountMenu: View {
    @EnvironmentObject var accounts: AccountStore
    @State private var showing = false
    var body: some View {
        Button { showing = true } label: { Image(systemName: "person.crop.circle.fill").font(.title2).padding(10).background(.regularMaterial, in: Circle()) }
            .overlay(alignment: .topTrailing) {
                if !accounts.unreadMessages.isEmpty {
                    Text("\(accounts.unreadMessages.count)")
                        .font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                        .padding(.horizontal, 5).frame(minWidth: 20, minHeight: 20)
                        .background(.red, in: Capsule()).overlay(Capsule().stroke(.white, lineWidth: 1))
                        .offset(x: 4, y: -2).allowsHitTesting(false)
                }
            }
            .accessibilityLabel("Account and messages, \(accounts.unreadMessages.count) unread")
            .sheet(isPresented: $showing, onDismiss: accounts.openRequestedCommunity) { AccountPanel().environmentObject(accounts) }
    }
}
private struct AccountPanel: View {
    @EnvironmentObject var accounts: AccountStore
    @Environment(\.dismiss) var dismiss
    @State private var pendingCommunityRemoval: MemberProfile?
    @State private var inboxPresented = false
    @State private var ownerMapPresented = false
    @State private var broadcastPresented = false
    @State private var pendingDelete: MemberProfile?
    @State private var recipient: MemberProfile?
    @State private var draft = ""
    var body: some View {
        NavigationStack {
            List {
                Section("Your account") {
                    ProfileAvatar(photo: accounts.profile?.profile_photo, size: 64)
                    Text(accounts.profile?.username ?? "")
                    Text(accounts.profile?.email ?? "").font(.caption)
                    if accounts.profile?.is_owner == false {
                        Toggle("Share location with builder", isOn: Binding(get: { accounts.profile?.share_location == true && !accounts.locationSharingPaused }, set: { value in Task { await accounts.updateSharing(value) } })).disabled(accounts.busy)
                        Text("Sharing includes your spoofing status and coordinates, or device-reported location when not spoofing. Turning it off stops new sharing immediately; stored server coordinates clear when connected.").font(.caption).foregroundStyle(.secondary)
                    }
                    Button("Sign out", role: .destructive) { Task { await accounts.signOut(); dismiss() } }
                }
                        Section("Community") {
                    Button { accounts.communityRequested = true; dismiss() } label: { Label("Community map", systemImage: "person.3.fill") }
                    if accounts.profile?.is_owner == false, accounts.profile?.community_enabled == true {
                        Button("Leave Community map", role: .destructive) { Task { _ = await accounts.updateCommunity(false) } }.disabled(accounts.busy)
                    }
                }
                if !accounts.notice.isEmpty { Text(accounts.notice).foregroundStyle(.orange) }
                Section("Messages from the builder") {
                    Button { inboxPresented = true } label: {
                        HStack { Label("Inbox", systemImage: "tray.fill"); Spacer(); if !accounts.unreadMessages.isEmpty { Text("\(accounts.unreadMessages.count) unread").foregroundStyle(.red) } }
                    }
                    if !accounts.inboxError.isEmpty { Text(accounts.inboxError).font(.caption).foregroundStyle(.orange) }
                }
                if accounts.profile?.is_owner == true {
                    Section("Live activity") {
                        Button { ownerMapPresented = true } label: { Label("User map", systemImage: "map.fill") }
                        Text("A green dot means the app reported activity in the last 45 seconds. Users may already be offline; coordinates are last reported and optional.").font(.caption).foregroundStyle(.secondary)
                    }
                    Section("Announcements") {
                        Button { broadcastPresented = true } label: { Label("Send notif", systemImage: "megaphone.fill") }
                        Text("Send one message to every current user’s in-app inbox.").font(.caption).foregroundStyle(.secondary)
                    }
                    Section("Owner · \(accounts.members.count) accounts") {
                        ForEach(accounts.members) { member in
                            VStack(alignment: .leading, spacing: 8) {
                                MemberPresenceSummary(member: member)
                                Text(member.email).textSelection(.enabled)
                                if !member.tiktok.isEmpty { Text("TikTok: \(member.tiktok)") }
                                if !member.instagram.isEmpty { Text("Instagram: \(member.instagram)") }
                                if let source = member.referral_source, !source.isEmpty { Text("Heard about us: \(source)") }
                                if let handle = member.referral_handle, !handle.isEmpty { Text("Handle: \(handle)") }
                                if !member.is_owner {
                                    HStack {
                                        Button("Message") { recipient = member; draft = "" }.buttonStyle(.bordered)
                                        Button("Delete account", role: .destructive) { pendingDelete = member }.buttonStyle(.bordered)
                                    }.disabled(accounts.busy)
                                    Button(member.community_blocked == true ? "Restore Community map eligibility" : "Remove from Community map", role: member.community_blocked == true ? nil : .destructive) {
                                        pendingCommunityRemoval = member
                                    }.disabled(accounts.busy)
                                } else { Text("Owner").font(.caption).foregroundStyle(.cyan) }
                            }.padding(.vertical, 6)
                        }
                    }
                }
            }
            .navigationTitle(accounts.profile?.is_owner == true ? "Owner dashboard" : "Account")
            .toolbar { Button("Done") { dismiss() } }
            .task {
                await accounts.refresh(); await accounts.loadMessages()
                while !Task.isCancelled, accounts.profile?.is_owner == true {
                    await accounts.loadMembers()
                    do { try await Task.sleep(for: .seconds(15)) } catch { return }
                }
            }
            .refreshable { await accounts.refresh(); await accounts.loadMembers() }
            .confirmationDialog("Permanently delete \(pendingDelete?.username ?? "this account")?", isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }), titleVisibility: .visible) {
                Button("Delete account and messages", role: .destructive) { if let member = pendingDelete { Task { await accounts.deleteMember(member) } }; pendingDelete = nil }
            } message: { Text("This deletes their online account on every device. It cannot erase an offline app installation or its local route history.") }
            .confirmationDialog("Change this user’s Community map access?", isPresented: Binding(get: { pendingCommunityRemoval != nil }, set: { if !$0 { pendingCommunityRemoval = nil } }), titleVisibility: .visible) {
                if let member = pendingCommunityRemoval {
                    Button(member.community_blocked == true ? "Restore eligibility" : "Remove and disable Community map") {
                        Task { await accounts.removeFromCommunity(member, blocked: member.community_blocked != true) }
                        pendingCommunityRemoval = nil
                    }
                }
            } message: { Text("Removal hides their community pin and prevents rejoining until you restore eligibility. Restoring eligibility does not opt them in; they must choose to join again. Private owner-location sharing is separate.") }
            .safeAreaInset(edge: .top) {
                if !inboxPresented { MessageArrivalBanner(openInbox: { inboxPresented = true }).environmentObject(accounts) }
            }
            .sheet(isPresented: $inboxPresented) { MessageInboxView().environmentObject(accounts) }
            .sheet(isPresented: $ownerMapPresented) { OwnerPresenceMap().environmentObject(accounts) }
            .sheet(isPresented: $broadcastPresented) { BroadcastComposer().environmentObject(accounts) }
            .sheet(item: $recipient) { member in
                NavigationStack {
                    Form {
                        Section("To \(member.username)") { TextEditor(text: $draft).frame(minHeight: 160) }
                        Text("Delivered to their in-app inbox when online. This does not send a lock-screen push notification.").font(.caption)
                        Button("Send message") { Task { if await accounts.send(draft, to: member) { recipient = nil } } }.disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || draft.count > 2000)
                        if !accounts.notice.isEmpty { Text(accounts.notice).foregroundStyle(.orange) }
                    }.navigationTitle("Message user").toolbar { Button("Cancel") { recipient = nil } }
                }
            }
        }
    }
}

private struct PasswordEntry: View {
    let title: String
    @Binding var text: String
    var creating = false
    @State private var revealed = false
    var body: some View {
        HStack {
            Group {
                if revealed { TextField(title, text: $text) }
                else { SecureField(title, text: $text) }
            }
            .textContentType(creating ? .newPassword : .password)
            .textInputAutocapitalization(.never).autocorrectionDisabled()
            Button { revealed.toggle() } label: { Image(systemName: revealed ? "eye.slash" : "eye") }
                .buttonStyle(.plain)
                .accessibilityLabel(revealed ? "Hide \(title.lowercased())" : "Show \(title.lowercased())")
        }
    }
}

private struct BroadcastComposer: View {
    @EnvironmentObject private var accounts: AccountStore
    @Environment(\.dismiss) private var dismiss
    @State private var draft = ""
    @State private var requestID = UUID()
    @State private var confirming = false
    var body: some View {
        NavigationStack {
            Form {
                Section("Message to all users") {
                    TextEditor(text: $draft).frame(minHeight: 160).disabled(accounts.busy)
                    Text("\(draft.count) / 2,000 characters").font(.caption).foregroundStyle(.secondary)
                }
                Text("Delivered to every currently registered user’s in-app inbox when they connect. This does not send lock-screen push notifications.").font(.caption)
                Button("Send notif to everyone") { confirming = true }
                    .disabled(accounts.busy || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || draft.count > 2000)
                if accounts.busy { ProgressView("Sending…") }
                if !accounts.notice.isEmpty { Text(accounts.notice).foregroundStyle(.secondary) }
            }
            .navigationTitle("Send notif")
            .toolbar { Button("Cancel") { dismiss() }.disabled(accounts.busy) }
            .interactiveDismissDisabled(accounts.busy)
            .onChange(of: draft) { _, _ in requestID = UUID() }
            .confirmationDialog("Send this message to every user?", isPresented: $confirming, titleVisibility: .visible) {
                Button("Send to everyone") {
                    Task { if await accounts.broadcast(draft, requestID: requestID) { dismiss() } }
                }
            } message: { Text(draft) }
        }
    }
}
