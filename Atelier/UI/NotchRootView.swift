import SwiftUI

struct NotchRootView: View {
    @ObservedObject var viewModel: NotchViewModel
    @State private var settleScale: CGFloat = 1

    var body: some View {
        VStack(spacing: 0) {
            NotchShape()
                .fill(Color.black)
                .frame(width: viewModel.currentSize.width, height: viewModel.currentSize.height)
                .scaleEffect(settleScale, anchor: .top)
                .overlay(
                    HoverTrackingView { hovering in
                        viewModel.handle(hovering ? .hoverStarted : .hoverEnded)
                    }
                )
                .allowsHitTesting(true)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .allowsHitTesting(false)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: viewModel.state)
        .onChange(of: viewModel.spaceChangeTick) { _, _ in
            playSettleAnimation()
        }
    }

    /// A quick tuck-and-spring-back when landing on a new Space, so the
    /// notch staying fixed through the swipe (unavoidable — see
    /// `NotchViewModel.spaceChangeTick`) reads as an intentional arrival cue
    /// rather than an accidental float.
    private func playSettleAnimation() {
        withAnimation(.easeOut(duration: 0.12)) {
            settleScale = 0.55
        }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.5).delay(0.12)) {
            settleScale = 1
        }
    }
}
