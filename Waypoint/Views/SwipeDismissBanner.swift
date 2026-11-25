import SwiftUI

/// Follows the finger upward, dismisses on a deliberate swipe/flick, springs back otherwise.
struct SwipeDismissBanner<Content: View>: View {
    let onDismiss: () -> Void
    @ViewBuilder let content: () -> Content
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var offset: CGFloat = 0
    @State private var exiting = false
    @State private var removal: Task<Void, Never>?

    var body: some View {
        content()
            .offset(y: offset)
            .opacity(exiting ? 0 : max(0.4, 1 - Double(abs(offset)) / 300))
            .contentShape(Rectangle())
            .simultaneousGesture(
                DragGesture(minimumDistance: 8, coordinateSpace: .global)
                    .onChanged { value in
                        guard !exiting, abs(value.translation.height) > abs(value.translation.width) else { return }
                        offset = min(0, value.translation.height)
                    }
                    .onEnded { value in
                        guard !exiting else { return }
                        let upward = value.translation.height < -35
                        let flick = value.translation.height < -10 && value.predictedEndTranslation.height < -100
                        if abs(value.translation.height) > abs(value.translation.width), upward || flick { dismiss() }
                        else { withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { offset = 0 } }
                    }
            )
            .accessibilityAction(named: "Dismiss notice") { dismiss() }
            .onDisappear { removal?.cancel() }
    }
    private func dismiss() {
        guard !exiting else { return }
        if reduceMotion { onDismiss(); return }
        withAnimation(.easeOut(duration: 0.2)) { offset = -180; exiting = true }
        removal = Task { @MainActor in
            do { try await Task.sleep(for: .milliseconds(200)) } catch { return }
            guard !Task.isCancelled else { return }
            onDismiss()
        }
    }
}
