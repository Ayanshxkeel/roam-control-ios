import SwiftUI
import MapKit

struct CommunityMapView: View {
    let onAccessGranted: () -> Void
    @EnvironmentObject private var accounts: AccountStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var phase
    var body: some View {
        NavigationStack {
            Group {
                if accounts.canUseCommunity && !accounts.needsCommunityRetentionConsent {
                    ProgressView("Opening Community map…").task { onAccessGranted() }
                }
                else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            Image(systemName: "person.3.fill").font(.largeTitle).foregroundStyle(.cyan)
                            Text("Join the Community map").font(.title.bold())
                            if accounts.profile?.community_blocked == true {
                                Text("The owner has removed your Community map access. You can still use the rest of Roam Control. Contact the builder if you believe this is a mistake.")
                            } else {
                                Text("This helps the app’s community features work better: you can discover other users in your area. If you don’t allow sharing, you can’t use the Community map. The rest of the app remains available.")
                                Text("By joining, you allow your approximate location, username, profile photo and spoofing status to appear to other signed-in Community map members and the owner. When you are not spoofing, the location comes from your device. Coordinates are rounded to roughly a kilometre; this does not guarantee anonymity. The owner can view the map without joining.")
                                Text("Reports update while the app is open and online. Other members see your pin for up to 10 minutes after the last report. The owner can keep seeing your last shared approximate pin after you close the app or sign out, until you leave Community map or are removed. This is a last-known report, not live tracking while the app is closed. You can leave anytime; offline removal takes effect on the server when you reconnect. Private location sharing with the owner is a separate setting. Messaging and dating are not included in this map.").font(.footnote).foregroundStyle(.secondary)
                                if accounts.profile?.community_enabled == true {
                                Text("Until you accept this update, the earlier 10-minute pin visibility limit still applies to the owner too.").font(.footnote).foregroundStyle(.secondary)
                            }
                            Button(accounts.profile?.community_enabled == true ? "Allow updated sharing" : "Allow and join Community map") { Task { _ = await accounts.updateCommunity(true) } }.buttonStyle(.borderedProminent).disabled(accounts.busy)
                            }
                            Button(accounts.profile?.community_enabled == true ? "Keep current sharing" : "Don’t allow") { dismiss() }.disabled(accounts.busy)
                            if accounts.busy { ProgressView() }
                            if !accounts.notice.isEmpty { Text(accounts.notice).foregroundStyle(.orange) }
                        }.padding(24)
                    }
                }
            }
            .navigationTitle("Community map")
            .toolbar {
                Button("Done") { dismiss() }

            }
            .task { await accounts.refresh() }
        }
    }
}
