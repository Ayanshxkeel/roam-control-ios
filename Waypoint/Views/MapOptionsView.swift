import SwiftUI

struct MapOptionsView: View {
    enum Action { case selectedLookAround, currentLookAround, zoom }
    @Binding var mapAppearance: String
    @Binding var pinAppearance: String
    @Binding var drivingPOV: Bool
    let canLookAroundCurrent: Bool
    let action: (Action) -> Void
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                Picker("Map style", selection: $mapAppearance) {
                    ForEach(["Standard", "Satellite", "Hybrid"], id: \.self) { Text($0).tag($0) }
                }
                Picker("Your pin", selection: $pinAppearance) {
                    Label("Classic", systemImage: "mappin.circle.fill").tag("mappin.circle.fill")
                    Label("Glowing orb", systemImage: "circle.fill").tag("circle.fill")
                    Label("Car", systemImage: "car.fill").tag("car.fill")
                    Label("Bike", systemImage: "bicycle").tag("bicycle")
                    Label("Walking", systemImage: "figure.walk").tag("figure.walk")
                    Label("Rocket", systemImage: "paperplane.fill").tag("paperplane.fill")
                    Label("Star", systemImage: "star.fill").tag("star.fill")
                }
                Toggle("Driving camera (3D)", isOn: $drivingPOV)
                Button("Zoom to selected pin") { action(.zoom) }
                Button("Look Around selected pin") { action(.selectedLookAround) }
                Button("Look Around current spoofed location") { action(.currentLookAround) }.disabled(!canLookAroundCurrent)
            }.navigationTitle("Map controls").toolbar { Button("Done") { dismiss() } }
        }
    }
}

struct PulsingMapPin: View {
    let symbol: String
    let color: Color
    let pitch: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false
    var body: some View {
        ZStack {
            ForEach(0..<5) { layer in
                Image(systemName: symbol).foregroundStyle(color.opacity(0.35 + Double(layer) * 0.1))
                    .offset(x: Double(4 - layer) * 0.3, y: Double(4 - layer) * 0.55)
            }
            Image(systemName: symbol).foregroundStyle(color.gradient)
        }
        .font(.system(size: 18, weight: .bold))
        .shadow(color: color.opacity(pulse ? 0.95 : 0.5), radius: pulse ? 6.5 : 3)
        .rotation3DEffect(.degrees(min(65, pitch) * 0.65), axis: (x: 1, y: -0.2, z: 0))
        .scaleEffect(pulse && !reduceMotion ? 1.08 : 1)
        .padding(4)
        .frame(width: 44, height: 44)
        .onAppear { if !reduceMotion { withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) { pulse = true } } }
    }
}
