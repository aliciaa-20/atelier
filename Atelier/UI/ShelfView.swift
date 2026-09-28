import AppKit
import SwiftUI

struct ShelfView: View {
    @ObservedObject var store: ShelfStore
    let rootDirectory: URL
    /// Same reasoning as `PeekPlayerView.notchHeight`: the physical notch
    /// cutout has no display pixels, so content starts below it.
    let notchHeight: CGFloat

    var body: some View {
        Group {
            if store.items.isEmpty {
                // Same empty-state style as the Camera tab's placeholder: a
                // soft card, one icon, one short line. Purely visual, so it
                // never swallows the drop (Invariant 4).
                VStack(spacing: 6) {
                    Image(systemName: "tray.and.arrow.down")
                        .font(.system(size: 22, weight: .regular))
                    Text("Drop files here")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundStyle(.white.opacity(0.5))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: NotchLayout.cardCornerRadius, style: .continuous)
                        .fill(Color.white.opacity(0.06))
                )
                .padding(.horizontal, NotchLayout.pageHorizontalInset)
                .allowsHitTesting(false)
            } else {
                // A single row, not a multi-row grid -- adapted from
                // TheBoredTeam/boring.notch's own `ShelfView` (read via
                // `gh api` per check-reference-apps-first), which uses a
                // plain `HStack` here too. A prior `LazyHGrid(rows:
                // [.adaptive])` computed its row count from whatever height
                // its parent proposed, which isn't reliably bounded to
                // exactly one row's worth here -- with enough items it grew
                // extra rows that overflowed *vertically* past the visible
                // area (silently clipped, since this is a horizontal-only
                // `ScrollView`) instead of extending horizontally into
                // scrollable space. A single row can only ever overflow in
                // the one direction that's actually scrollable.
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(store.items) { item in
                            ShelfItemCell(item: item, rootDirectory: rootDirectory) {
                                store.remove(item.id)
                            }
                        }
                    }
                    .padding(.horizontal, NotchLayout.pageHorizontalInset)
                }
            }
        }
        .padding(.top, notchHeight + 8)
        .padding(.bottom, NotchLayout.pageBottomInset)
    }
}

private struct ShelfItemCell: View {
    let item: ShelfItem
    let rootDirectory: URL
    let onRemove: () -> Void
    @State private var isHovering = false
    @State private var dragPreviewImage: NSImage?
    @State private var thumbnail: NSImage?

    private var fileURL: URL { item.storageURL(root: rootDirectory) }
    private var fileIcon: NSImage { NSWorkspace.shared.icon(forFile: fileURL.path) }
    /// The real content preview once `ShelfThumbnailService` resolves one
    /// (e.g. a PDF's actual first page), falling back to the plain file-type
    /// icon until then or if QuickLook has nothing to render for this type.
    private var displayImage: NSImage { thumbnail ?? fileIcon }

    var body: some View {
        VStack(spacing: 4) {
            ZStack(alignment: .topTrailing) {
                Image(nsImage: displayImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 40, height: 40)
                    .overlay(
                        ShelfDragSourceView(fileURL: fileURL, previewImage: dragPreviewImage ?? displayImage)
                    )

                if isHovering {
                    Button(action: onRemove) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.white, .black.opacity(0.6))
                            .font(.system(size: 14))
                    }
                    .buttonStyle(SoftPressButtonStyle())
                    .accessibilityLabel("Remove \(item.originalFilename)")
                    .help("Remove from shelf")
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
        .task(id: fileURL) {
            thumbnail = await ShelfThumbnailService.shared.thumbnail(for: fileURL, size: CGSize(width: 80, height: 80))
            dragPreviewImage = await renderDragPreview()
        }
        // The remove button only exists while the pointer hovers, and VoiceOver
        // never moves the pointer: one element per file, with Remove as an action.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.originalFilename)
        .accessibilityHint("Drag to move it out of the shelf")
        .accessibilityAction(named: "Remove from shelf", onRemove)
    }

    @MainActor
    private func renderDragPreview() async -> NSImage {
        let renderer = ImageRenderer(content: ShelfDragPreviewContent(icon: displayImage, filename: item.originalFilename))
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        return renderer.nsImage ?? displayImage
    }
}

/// What the drag ghost actually looks like -- icon plus filename, matching
/// the cell itself, so dragging a shelf item out shows what's being dragged
/// instead of a generic file glyph.
private struct ShelfDragPreviewContent: View {
    let icon: NSImage
    let filename: String

    var body: some View {
        VStack(spacing: 4) {
            Image(nsImage: icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 40, height: 40)
            Text(filename)
                .font(.caption2)
                .foregroundStyle(.white)
                .lineLimit(1)
                .frame(width: 64)
        }
        .padding(6)
    }
}

/// Drag-out source for a shelf item. SwiftUI's `.onDrag` only ever shows a
/// generic system preview -- there's no way to hand it a custom drag image --
/// so this hand-rolls `NSDraggingSource` instead, adapted from
/// TheBoredTeam/boring.notch's `ShelfItemView.DraggableClickView` (read via
/// `gh api` per check-reference-apps-first). A prior from-scratch attempt at
/// this was dropped after its `lockFocus`/`unlockFocus`-drawn preview image
/// didn't survive the Drag Manager's out-of-process compositor; this renders
/// the preview via SwiftUI's `ImageRenderer` instead (`renderDragPreview`
/// above), matching what boring.notch actually ships.
private struct ShelfDragSourceView: NSViewRepresentable {
    let fileURL: URL
    let previewImage: NSImage

    func makeNSView(context: Context) -> ShelfDragSourceNSView {
        let view = ShelfDragSourceNSView()
        view.fileURL = fileURL
        view.previewImage = previewImage
        return view
    }

    func updateNSView(_ nsView: ShelfDragSourceNSView, context: Context) {
        nsView.fileURL = fileURL
        nsView.previewImage = previewImage
    }
}

private final class ShelfDragSourceNSView: NSView, NSDraggingSource {
    var fileURL: URL?
    var previewImage: NSImage?

    private var mouseDownEvent: NSEvent?
    private let dragThreshold: CGFloat = 3

    /// Same reasoning as ADR 0003's `ClickThroughHostingView`: the panel is
    /// a nonactivating panel, so a raw `NSView`'s `mouseDown` never arrives
    /// here without this override.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        mouseDownEvent = event
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = mouseDownEvent else {
            super.mouseDragged(with: event)
            return
        }
        let distance = hypot(
            event.locationInWindow.x - start.locationInWindow.x,
            event.locationInWindow.y - start.locationInWindow.y
        )
        guard distance > dragThreshold else { return }
        mouseDownEvent = nil
        startDragSession(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        mouseDownEvent = nil
    }

    private func startDragSession(with event: NSEvent) {
        guard let fileURL, let previewImage else { return }
        let draggingItem = NSDraggingItem(pasteboardWriter: fileURL as NSURL)
        draggingItem.setDraggingFrame(
            NSRect(origin: .zero, size: previewImage.size),
            contents: previewImage
        )
        beginDraggingSession(with: [draggingItem], event: event, source: self)
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .copy
    }
}
