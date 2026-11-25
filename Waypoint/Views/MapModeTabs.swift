import SwiftUI

struct MapModeTabs: View {
    let communitySelected: Bool
    let selectRegular: () -> Void
    let selectCommunity: () -> Void
    @Namespace private var underline
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 26) {
            tab("Regular map", selected: !communitySelected, action: selectRegular)
            tab("Community map", selected: communitySelected, action: selectCommunity)
        }
        .buttonStyle(.plain)
        .padding(.top, 2)
        .frame(maxWidth: .infinity)
        .animation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.85), value: communitySelected)
    }

    private func tab(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Text(title)
                    .font(.system(size: 14, weight: selected ? .bold : .semibold))
                    .foregroundStyle(.white.opacity(selected ? 1 : 0.65))
                    .shadow(color: .black.opacity(0.85), radius: 3, y: 1)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                ZStack {
                    Color.clear.frame(width: 26, height: 3)
                    if selected {
                        Capsule().fill(.white).frame(width: 26, height: 3)
                            .shadow(color: .black.opacity(0.7), radius: 2)
                            .matchedGeometryEffect(id: "selected-map-tab", in: underline)
                    }
                }
            }
            .padding(.horizontal, 3)
            .frame(minHeight: 36)
            .contentShape(Rectangle())
        }
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
