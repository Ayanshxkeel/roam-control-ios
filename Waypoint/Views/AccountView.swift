import SwiftUI

struct AccountGate: View {
    @StateObject private var accounts = AccountStore()
    @Environment(\.scenePhase) private var phase
    var body: some View {
        Group {
            if !accounts.checked { ProgressView("Checking your account…") }
            else if accounts.profile != nil {
                RootView().overlay(alignment: .topTrailing) {
                    AccountMenu().environmentObject(accounts).padding(.top, 58).padding(.trailing, 12)
                }
            } else { SignInView().environmentObject(accounts) }
        }
        .task { await accounts.restore() }
        .task(id: phase) {
            guard phase == .active else { return }
            while !Task.isCancelled {
                if accounts.profile != nil { await accounts.refresh() }
                do { try await Task.sleep(for: .seconds(30)) } catch { return }
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
    @State private var tiktok = ""
    @State private var instagram = ""
    @State private var stay = true
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
                            if creating && !ownerLogin { TextField("Username", text: $username).textContentType(.username) }
                            TextField("Email", text: $email).keyboardType(.emailAddress).textContentType(.emailAddress)
                            SecureField("Password", text: $password).textContentType(creating ? .newPassword : .password)
                            if ownerLogin {
                                SecureField("Owner password 2", text: $password2)
                                SecureField("Owner password 3", text: $password3)
                            }
                            if creating && !ownerLogin {
                                TextField("TikTok username (optional)", text: $tiktok)
                                TextField("Instagram username (optional)", text: $instagram)
                            }
                        }.textFieldStyle(.roundedBorder).textInputAutocapitalization(.never).autocorrectionDisabled()
                        Toggle("Owner sign-in", isOn: $ownerLogin).onChange(of: ownerLogin) { _, value in if value { creating = false } }
                        Toggle("Stay logged in", isOn: $stay)
                        if creating {
                            Text("Account details are stored online. The owner can see your username, email and social handles, delete your account, and send you messages. Passwords are never visible to the owner.").font(.footnote).foregroundStyle(.secondary)
                            Text("Failing to follow @ayanshxkeel on TikTok may result in removal of your account. Follow status is not automatically verified.").font(.footnote)
                            Link("Follow @ayanshxkeel", destination: URL(string: "https://www.tiktok.com/@ayanshxkeel")!)
                        }
                        if !accounts.notice.isEmpty { Text(accounts.notice).foregroundStyle(.orange).accessibilityLabel(accounts.notice) }
                        if !accounts.configured { Text("Online accounts are awaiting server setup.").font(.footnote).foregroundStyle(.secondary) }
                        Button {
                            Task {
                                await accounts.authenticate(signUp: creating, username: username, email: email, password: password, tiktok: tiktok, instagram: instagram, stay: stay, ownerPasswords: ownerLogin ? [password, password2, password3] : nil)
                                password = ""; password2 = ""; password3 = ""
                            }
                        } label: {
                            HStack { Spacer(); if accounts.busy { ProgressView() }; Text(ownerLogin ? "Owner sign-in" : (creating ? "Create account" : "Sign in")); Spacer() }.padding(8)
                        }.buttonStyle(.borderedProminent)
                            .disabled(accounts.busy || (ownerLogin && (password2.isEmpty || password3.isEmpty)) || !accounts.configured || email.isEmpty || password.isEmpty || (creating && (username.trimmingCharacters(in: .whitespaces).isEmpty || password.count < 8)))
                        if creating { Text("Use at least 8 characters for your password. Your account is available immediately after sign-up.").font(.caption).foregroundStyle(.secondary) }
                    }.padding(28).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 30)).padding()
                }
            }
        }
    }
}
private struct AccountMenu: View {
    @EnvironmentObject var accounts: AccountStore
    @State private var showing = false
    var body: some View {
        Button { showing = true } label: { Image(systemName: "person.crop.circle.fill").font(.title2).padding(10).background(.regularMaterial, in: Circle()) }.accessibilityLabel("Account and messages")
            .sheet(isPresented: $showing) { AccountPanel().environmentObject(accounts) }
    }
}
private struct AccountPanel: View {
    @EnvironmentObject var accounts: AccountStore
    @Environment(\.dismiss) var dismiss
    @State private var pendingDelete: MemberProfile?
    @State private var recipient: MemberProfile?
    @State private var draft = ""
    var body: some View {
        NavigationStack {
            List {
                Section("Your account") {
                    Text(accounts.profile?.username ?? "")
                    Text(accounts.profile?.email ?? "").font(.caption)
                    Button("Sign out", role: .destructive) { Task { await accounts.signOut(); dismiss() } }
                }
                if !accounts.notice.isEmpty { Text(accounts.notice).foregroundStyle(.orange) }
                Section("Messages from the builder") {
                    if accounts.messages.isEmpty { Text("No messages yet").foregroundStyle(.secondary) }
                    ForEach(accounts.messages) { message in VStack(alignment: .leading, spacing: 6) { Text(message.body); Text(message.created_at).font(.caption).foregroundStyle(.secondary) } }
                }
                if accounts.profile?.is_owner == true {
                    Section("Owner · \(accounts.members.count) accounts") {
                        ForEach(accounts.members) { member in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(member.username).font(.headline)
                                Text(member.email).textSelection(.enabled)
                                if !member.tiktok.isEmpty { Text("TikTok: \(member.tiktok)") }
                                if !member.instagram.isEmpty { Text("Instagram: \(member.instagram)") }
                                if !member.is_owner {
                                    HStack {
                                        Button("Message") { recipient = member; draft = "" }.buttonStyle(.bordered)
                                        Button("Delete account", role: .destructive) { pendingDelete = member }.buttonStyle(.bordered)
                                    }.disabled(accounts.busy)
                                } else { Text("Owner").font(.caption).foregroundStyle(.cyan) }
                            }.padding(.vertical, 6)
                        }
                    }
                }
            }
            .navigationTitle(accounts.profile?.is_owner == true ? "Owner dashboard" : "Account")
            .toolbar { Button("Done") { dismiss() } }
            .task { await accounts.loadMembers() }
            .refreshable { await accounts.refresh(); await accounts.loadMembers() }
            .confirmationDialog("Permanently delete \(pendingDelete?.username ?? "this account")?", isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }), titleVisibility: .visible) {
                Button("Delete account and messages", role: .destructive) { if let member = pendingDelete { Task { await accounts.deleteMember(member) } }; pendingDelete = nil }
            } message: { Text("This deletes their online account on every device. It cannot erase an offline app installation or its local route history.") }
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
