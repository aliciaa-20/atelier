import SwiftUI
import AppKit

/// Detects a file drag entering/exiting/dropping on the notch panel's own
/// screen region. Adapted from TheBoredTeam/boring.notch's `DragDetector`
/// (read via `gh api` per check-reference-apps-first): global `NSEvent`
/// monitors on mouse down/dragged/up, using the drag pasteboard's
/// `changeCount` to distinguish real dragged content from a plain click.
/// Mirrors the AppKit boundary `NotchGestureModifier`/`NotchGestureInterpreter`
/// already establish (Invariant 8) -- raw `NSEvent`/`NSPasteboard` never
/// crosses past this file; `NotchRootView` only sees the three closures
/// below. Manual-verification only -- no real drag session in CI, same
/// treatment as `NotchGestureModifier`.
struct NotchDragModifier: ViewModifier {
    let onDragEntered: () -> Void
    let onDragExited: () -> Void
    let onDrop: ([URL]) -> Void

    func body(content: Content) -> some View {
        content.background(
            NotchDragMonitorRepresentable(onDragEntered: onDragEntered, onDragExited: onDragExited, onDrop: onDrop)
        )
    }
}

private struct NotchDragMonitorRepresentable: NSViewRepresentable {
    let onDragEntered: () -> Void
    let onDragExited: () -> Void
    let onDrop: ([URL]) -> Void

    func makeNSView(context: Context) -> NotchDragMonitorView {
        let view = NotchDragMonitorView()
        view.update(onDragEntered: onDragEntered, onDragExited: onDragExited, onDrop: onDrop)
        return view
    }

    func updateNSView(_ nsView: NotchDragMonitorView, context: Context) {
        nsView.update(onDragEntered: onDragEntered, onDragExited: onDragExited, onDrop: onDrop)
    }

    static func dismantleNSView(_ nsView: NotchDragMonitorView, coordinator: ()) {
        nsView.stopMonitoring()
    }
}

@MainActor private final class NotchDragMonitorView: NSView {
    private var mouseDownMonitor: Any?
    private var mouseDraggedMonitor: Any?
    private var mouseUpMonitor: Any?

    private var onDragEntered: (() -> Void)?
    private var onDragExited: (() -> Void)?
    private var onDrop: (([URL]) -> Void)?

    private let dragPasteboard = NSPasteboard(name: .drag)
    private var pasteboardChangeCount = -1
    private var isDragging = false
    private var isContentDragging = false
    private var hasEnteredRegion = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        installMonitorsIfNeeded()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    isolated deinit {
        if let mouseDownMonitor { NSEvent.removeMonitor(mouseDownMonitor) }
        if let mouseDraggedMonitor { NSEvent.removeMonitor(mouseDraggedMonitor) }
        if let mouseUpMonitor { NSEvent.removeMonitor(mouseUpMonitor) }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        installMonitorsIfNeeded()
    }

    func update(onDragEntered: @escaping () -> Void, onDragExited: @escaping () -> Void, onDrop: @escaping ([URL]) -> Void) {
        self.onDragEntered = onDragEntered
        self.onDragExited = onDragExited
        self.onDrop = onDrop
    }

    func stopMonitoring() {
        if let mouseDownMonitor { NSEvent.removeMonitor(mouseDownMonitor) }
        if let mouseDraggedMonitor { NSEvent.removeMonitor(mouseDraggedMonitor) }
        if let mouseUpMonitor { NSEvent.removeMonitor(mouseUpMonitor) }
        mouseDownMonitor = nil
        mouseDraggedMonitor = nil
        mouseUpMonitor = nil
    }

    /// Same reasoning as `NotchGestureMonitorView.hitTest`: this view exists
    /// purely to install `NSEvent` monitors, which fire regardless of
    /// AppKit hit-testing, so it must not intercept clicks meant for the
    /// SwiftUI content above it.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

private extension NotchDragMonitorView {
    func installMonitorsIfNeeded() {
        if mouseDownMonitor == nil {
            mouseDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
                self?.handleMouseDown()
            }
        }
        if mouseDraggedMonitor == nil {
            mouseDraggedMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDragged) { [weak self] _ in
                self?.handleMouseDragged()
            }
        }
        if mouseUpMonitor == nil {
            mouseUpMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { [weak self] _ in
                self?.handleMouseUp()
            }
        }
    }

    func handleMouseDown() {
        pasteboardChangeCount = dragPasteboard.changeCount
        isDragging = true
        isContentDragging = false
        hasEnteredRegion = false
    }

    func handleMouseDragged() {
        guard isDragging else { return }

        if !isContentDragging, dragPasteboard.changeCount != pasteboardChangeCount, hasValidDragContent() {
            isContentDragging = true
        }
        guard isContentDragging, let screenRect = currentScreenRect() else { return }

        let containsMouse = screenRect.contains(NSEvent.mouseLocation)
        if containsMouse, !hasEnteredRegion {
            hasEnteredRegion = true
            onDragEntered?()
        } else if !containsMouse, hasEnteredRegion {
            hasEnteredRegion = false
            onDragExited?()
        }
    }

    func handleMouseUp() {
        guard isDragging else { return }
        if isContentDragging, hasEnteredRegion, let urls = draggedFileURLs() {
            onDrop?(urls)
        } else if hasEnteredRegion {
            onDragExited?()
        }
        isDragging = false
        isContentDragging = false
        hasEnteredRegion = false
        pasteboardChangeCount = -1
    }

    func hasValidDragContent() -> Bool {
        dragPasteboard.types?.contains(.fileURL) ?? false
    }

    /// Real file URLs straight off the drag pasteboard -- deliberately not
    /// wrapped in `NSItemProvider`. A prior version routed these through
    /// `NSItemProvider(contentsOf:)` +
    /// `loadFileRepresentation(forTypeIdentifier: "public.item")` at the
    /// call site, which silently renamed dropped files to a generic
    /// "<type description>.<ext>" name (e.g. "PDF document.pdf" instead of
    /// the real filename) -- `"public.item"` doesn't exactly match how the
    /// pasteboard registered the file's UTI, so the system synthesized a
    /// fresh temp copy instead of handing back the original. We already
    /// have the real URL here; no synthesis needed.
    func draggedFileURLs() -> [URL]? {
        guard let urls = dragPasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL], !urls.isEmpty else {
            return nil
        }
        return urls
    }

    func currentScreenRect() -> CGRect? {
        guard let window else { return nil }
        let rectInWindow = convert(bounds, to: nil)
        return window.convertToScreen(rectInWindow)
    }
}
