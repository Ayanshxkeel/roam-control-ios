import SwiftUI

struct MessageArrivalBanner: View {
    @EnvironmentObject private var accounts: AccountStore
    let openInbox: () -> Void
    var body: some View {
        if let message = accounts.pendingMessage {
            SwipeDismissBanner(onDismiss: { withAnimation { accounts.dismissPendingAlerts() } }) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label(message.is_safety_report == true ? "New destination report" : accounts.unreadMessages.count == 1 ? "New message" : "\(accounts.unreadMessages.count) unread messages", systemImage: "bell.badge.fill").font(.headline)
                        Spacer()
                        Button { withAnimation { accounts.dismissPendingAlerts() } } label: { Image(systemName: "xmark") }.accessibilityLabel("Dismiss message alert, keep unread")
                    }
                    Text(message.body).font(.subheadline).lineLimit(4)
                    Button("Open inbox", action: openInbox).font(.subheadline.bold())
                }.padding(14).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
            }
            .id(message.id)
            .padding(.horizontal, 12).padding(.top, 6)
        }
    }
}

struct MessageInboxView: View {
    @State private var selectedMember: MemberProfile?
    @State private var profileError = ""
    @EnvironmentObject private var accounts: AccountStore
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                if !profileError.isEmpty { Text(profileError).foregroundStyle(.orange) }
                if !accounts.inboxError.isEmpty { Text(accounts.inboxError).foregroundStyle(.orange) }
                if accounts.messages.isEmpty {
                    if accounts.inboxLoading { ProgressView("Loading messages…") }
                    else { Text("No messages yet").foregroundStyle(.secondary) }
                }
                ForEach(accounts.messages) { message in
                    VStack(alignment: .leading, spacing: 8) {
                        Label(message.is_safety_report == true ? "Destination check-in" : "From the builder", systemImage: "person.crop.circle.badge.checkmark").font(.caption).foregroundStyle(.secondary)
                        Text(message.body).textSelection(.enabled)
                        if accounts.profile?.is_owner == true, let id = message.subject_user_id {
                            Button("View user profile & reports") {
                                Task {
                                    do { selectedMember = try await accounts.fetchMember(id); profileError = "" }
                                    catch { profileError = error.localizedDescription }
                                }
                            }
                        }
                        Text(message.created_at).font(.caption2).foregroundStyle(.secondary)
                    }.padding(.vertical, 6)
                }
            }
            .sheet(item: $selectedMember) { member in SafetyUserProfileView(member: member).environmentObject(accounts) }
            .navigationTitle("Inbox")
            .toolbar { Button("Done") { dismiss() } }
            .task { await accounts.loadMessages(); accounts.markMessagesRead() }
            .onChange(of: accounts.messages.map(\.id)) { _, _ in accounts.markMessagesRead() }
            .refreshable { await accounts.loadMessages(); accounts.markMessagesRead() }
        }
    }
}
