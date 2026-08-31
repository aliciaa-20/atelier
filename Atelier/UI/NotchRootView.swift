import SwiftUI

struct NotchRootView: View {
    @ObservedObject var viewModel: NotchViewModel

    var body: some View {
        VStack(spacing: 0) {
            NotchShape()
                .fill(Color.black)
                .frame(width: viewModel.currentSize.width, height: viewModel.currentSize.height)
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
    }
}
