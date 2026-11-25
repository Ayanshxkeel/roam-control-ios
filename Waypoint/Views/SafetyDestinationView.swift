import SwiftUI

struct SafetyDestinationView: View {
    @EnvironmentObject private var accounts: AccountStore
    @Environment(\.dismiss) private var dismiss
    let kind: String
    let onApproved: () -> Void
    @State private var destination = ""
    @State private var requestID = UUID()
    @State private var sending = false
    @State private var error = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label("Before you start spoofing", systemImage: "person.2.shield.checkmark").font(.headline)
                    Text("Please tell a trusted adult and a friend where you will actually be going, in case of an emergency.")
                    Text("Enter your actual destination below. This text will be sent to the Roam Control owner and saved on your account’s destination-report history. It is separate from your spoofed pin and is not shared on Community maps.")
                    Text("Providing a false destination may lead to account removal and loss of spoofing access. The app cannot verify this information and this is not an emergency-response service.").font(.footnote).foregroundStyle(.secondary)
                }
                Section("Where will you actually be going?") {
                    TextEditor(text: $destination).frame(minHeight: 110).accessibilityLabel("Actual destination shared with owner")
                    Text("\(destination.count)/1,000 characters").font(.caption).foregroundStyle(.secondary)
                }
                Section {
                    if !error.isEmpty { Text(error).foregroundStyle(.orange) }
                    Button {
                        sending = true; error = ""
                        Task {
                            do {
                                try await accounts.submitDestination(destination.trimmingCharacters(in: .whitespacesAndNewlines), kind: kind, requestID: requestID)
                                onApproved(); dismiss()
                            } catch {
                                self.error = "Could not send your destination. Connect to the internet and try again before starting. \(error.localizedDescription)"
                                sending = false
                            }
                        }
                    } label: {
                        if sending { ProgressView("Submitting…") }
                        else { Text("Submit & share with owner").fontWeight(.semibold) }
                    }.disabled(sending || destination.trimmingCharacters(in: .whitespacesAndNewlines).count < 3 || destination.count > 1000)
                    Text("Cancel closes this form without starting a new spoofing session.").font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Destination check-in")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(sending) } }
            .interactiveDismissDisabled(sending)
            .onChange(of: destination) { _, _ in requestID = UUID() }
            .disabled(sending)
        }
    }
}

struct SafetyUserProfileView: View {
    @EnvironmentObject private var accounts: AccountStore
    @Environment(\.dismiss) private var dismiss
    let member: MemberProfile
    @State private var reports: [SafetyReport] = []
    @State private var loading = true
    @State private var error = ""
    var body: some View {
        NavigationStack {
            List {
                Section("User profile") {
                    ProfileAvatar(photo: member.profile_photo, size: 64)
                    MemberPresenceSummary(member: member)
                    Text(member.email).textSelection(.enabled)
                    if !member.tiktok.isEmpty { Text("TikTok: \(member.tiktok)") }
                    if !member.instagram.isEmpty { Text("Instagram: \(member.instagram)") }
                    if let source = member.referral_source { Text("Source: \(source)") }
                    if let handle = member.referral_handle { Text("Social username: \(handle)") }
                }
                Section("Submitted actual destinations") {
                    Text("User-entered information; not independently verified. These are destination reports, not live GPS readings.").font(.caption).foregroundStyle(.secondary)
                    if loading { ProgressView() }
                    if !error.isEmpty { Text(error).foregroundStyle(.orange) }
                    if !loading && reports.isEmpty && error.isEmpty { Text("No destination reports yet").foregroundStyle(.secondary) }
                    ForEach(reports) { report in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(report.destination).textSelection(.enabled)
                            Text("\(report.kind.capitalized) · \(report.created_at)").font(.caption).foregroundStyle(.secondary)
                        }.padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle(member.username)
            .toolbar { Button("Done") { dismiss() } }
            .task { await load() }
            .refreshable { await load() }
        }
    }
    private func load() async {
        loading = true; error = ""
        do { reports = try await accounts.safetyHistory(for: member.id) }
        catch { self.error = error.localizedDescription }
        loading = false
    }
}
