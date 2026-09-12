import SwiftUI

struct ShelfView: View {
    @ObservedObject var store: ShelfStore
    let rootDirectory: URL
    /// Same reasoning as `PeekPlayerView.notchHeight`: the physical notch
    /// cutout has no display pixels, so content starts below it.
    let notchHeight: CGFloat

    private let columns = [GridItem(.adaptive(minimum: 64, maximum: 64), spacing: 12)]

    var body: some View {
        Group {
            if store.items.isEmpty {
                Text("Drop files here")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.6))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHGrid(rows: columns, spacing: 12) {
                        ForEach(store.items) { item in
                            ShelfItemCell(item: item, rootDirectory: rootDirectory) {
                                store.remove(item.id)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
        }
        .padding(.top, notchHeight + 8)
        .padding(.bottom, 10)
    }
}

private struct ShelfItemCell: View {
    let item: ShelfItem
    let rootDirectory: URL
    let onRemove: () -> Void
    @State private var isHovering = false

    private var fileURL: URL { item.storageURL(root: rootDirectory) }

    var body: some View {
        VStack(spacing: 4) {
            ZStack(alignment: .topTrailing) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: fileURL.path))
                    .resizable()
                    .frame(width: 40, height: 40)

                if isHovering {
                    Button(action: onRemove) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.white, .black.opacity(0.6))
                            .font(.system(size: 14))
                    }
                    .buttonStyle(.plain)
                    .offset(x: 6, y: -6)
                }
            }

            Text(item.originalFilename)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(1)
                .frame(width: 64)
        }
        .onHover { isHovering = $0 }
        .onDrag { NSItemProvider(contentsOf: fileURL) ?? NSItemProvider() }
    }
}
