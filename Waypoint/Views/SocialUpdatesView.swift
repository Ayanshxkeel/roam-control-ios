import SwiftUI

struct SocialUpdatesView: View {
    let continueToApp: () -> Void
    var body: some View {
        ZStack {
            LinearGradient(colors: [.cyan.opacity(0.28), .indigo.opacity(0.22), .clear], startPoint: .topLeading, endPoint: .bottomTrailing).ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Image(systemName: "megaphone.fill").font(.system(size: 52)).foregroundStyle(.cyan).accessibilityHidden(true)
                    Text("Stay in the loop").font(.largeTitle.bold())
                    Text("Check TikTok or Instagram daily for Roam Control updates.").font(.title3)
                    Text("Follow the builder on social media to stay up to date with the latest features, fixes, and new builds.").foregroundStyle(.secondary)
                    Group {
                        Link("TikTok · @ayanshxkeel", destination: URL(string: "https://www.tiktok.com/@ayanshxkeel")!)
                        Link("Instagram · @ayan.shxkeel", destination: URL(string: "https://www.instagram.com/ayan.shxkeel/")!)
                        Link("LinkedIn · Ayan Shakeel", destination: URL(string: "https://www.linkedin.com/in/ayan-shakeel/")!)
                        Link("GitHub · Ayanshxkeel", destination: URL(string: "https://github.com/Ayanshxkeel")!)
                        Link("Explore my other builds", destination: URL(string: "https://ayanshxkeel.github.io/")!)
                    }.font(.headline).frame(maxWidth: .infinity, alignment: .leading)
                    Button(action: continueToApp) {
                        Text("Continue to Roam Control").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 10)
                    }.buttonStyle(.borderedProminent)
                }.padding(26).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 30)).padding()
            }
        }
    }
}
