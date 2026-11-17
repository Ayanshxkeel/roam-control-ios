import SwiftUI

struct RootView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("support.lastPrompt") private var lastPrompt: Double = 0
    @State private var showingSupport = false

    private func offerSupport() {
        guard scenePhase == .active, !model.isSetupPresented, model.alert == nil,
              !Calendar.current.isDateInToday(Date(timeIntervalSince1970: lastPrompt))
        else { return }
        lastPrompt = Date().timeIntervalSince1970
        showingSupport = true
    }

    var body: some View {
        NavigationStack {
            MapSpoofView(openSupport: { showingSupport = true })
        }
        .sheet(isPresented: $model.isSetupPresented) {
            NavigationStack {
                SetupView()
            }
        }
        .sheet(isPresented: $showingSupport) {
            NavigationStack {
                Form {
                    Section("Support the builder for $0.99") {
                        Text("ayanshxkeel@gmail.com").textSelection(.enabled)
                    }
                    Section("Find the builder") {
                        if let tiktok = URL(string: "https://www.tiktok.com/@ayanshxkeel") {
                            Link("TikTok @ayanshxkeel", destination: tiktok)
                        }
                        if let builds = URL(string: "https://ayanshxkeel.github.io/") {
                            Link("Check out my other builds", destination: builds)
                        }
                        if let linkedin = URL(string: "https://www.linkedin.com/in/ayan-shakeel/") {
                            Link("LinkedIn", destination: linkedin)
                        }
                        if let instagram = URL(string: "https://www.instagram.com/ayan.shxkeel/") {
                            Link("Instagram @ayan.shxkeel", destination: instagram)
                        }
                        Text("Send feedback or ideas on TikTok or Instagram.")
                    }
                }
                .navigationTitle("Support the builder")
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { showingSupport = false }
                    }
                }
            }
        }
        .onChange(of: scenePhase, initial: true) { _, _ in offerSupport() }
        .alert(item: $model.alert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text("OK"))
            )
        }
    }
}

