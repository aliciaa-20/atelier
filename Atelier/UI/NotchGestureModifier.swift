import SwiftUI
import AppKit

/// Trackpad swipe detection over the notch panel. Structurally adapted
/// from jackson-storm/dynamicnotch's `NotchSwipeDismissModifier` and
/// Ebullioscopic/Atoll's `panGesture`/`ScrollMonitor` (both read via
/// `gh api` during Phase 7 design) -- local *and* global scroll-wheel
/// monitors, because the cursor may be at the very top screen edge,
/// outside the panel's own hit-testing region, when a swipe starts.
///
/// All gesture *resolution* (thresholds, direction locking, momentum
/// discarding) lives in the pure, unit-tested `NotchGestureInterpreter`;
/// this file only translates real `NSEvent`s into `NotchGestureDelta`
/// and dispatches the resulting action to a closure. Manual-verification
/// only -- no real trackpad in CI, same treatment as `AppleScriptRunner`.
struct NotchGestureModifier: ViewModifier {
    let capabilities: NotchGestureCapabilities
    let onOpen: () -> Void
    let onClose: () -> Void
    let onSkipForward: () -> Void
    let onSkipBackward: () -> Void

    func body(content: Content) -> some View {
        content.background(
            NotchGestureMonitorRepresentable(
                capabilities: capabilities,
                onOpen: onOpen,
                onClose: onClose,
                onSkipForward: onSkipForward,
                onSkipBackward: onSkipBackward
            )
        )
    }
}

private struct NotchGestureMonitorRepresentable: NSViewRepresentable {
    let capabilities: NotchGestureCapabilities
    let onOpen: () -> Void
    let onClose: () -> Void
    let onSkipForward: () -> Void
    let onSkipBackward: () -> Void

    func makeNSView(context: Context) -> NotchGestureMonitorView {
        let view = NotchGestureMonitorView()
        view.update(
            capabilities: capabilities,
            onOpen: onOpen,
            onClose: onClose,
            onSkipForward: onSkipForward,
            onSkipBackward: onSkipBackward
        )
        return view
    }

    func updateNSView(_ nsView: NotchGestureMonitorView, context: Context) {
        nsView.update(
            capabilities: capabilities,
            onOpen: onOpen,
            onClose: onClose,
            onSkipForward: onSkipForward,
            onSkipBackward: onSkipBackward
        )
    }

    static func dismantleNSView(_ nsView: NotchGestureMonitorView, coordinator: ()) {
        nsView.stopMonitoring()
    }
}

private final class NotchGestureMonitorView: NSView {
    private var localMonitor: Any?
    private var globalMonitor: Any?

    private var capabilities = NotchGestureCapabilities(canOpen: false, canClose: false, canSkip: false)
    private var onOpen: (() -> Void)?
    private var onClose: (() -> Void)?
    private var onSkipForward: (() -> Void)?
    private var onSkipBackward: (() -> Void)?

    private var trackingState = NotchGestureTrackingState()
    private var isTracking = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        installMonitorsIfNeeded()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        stopMonitoring()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        installMonitorsIfNeeded()
    }

    func update(
        capabilities: NotchGestureCapabilities,
        onOpen: @escaping () -> Void,
        onClose: @escaping () -> Void,
        onSkipForward: @escaping () -> Void,
        onSkipBackward: @escaping () -> Void
    ) {
        self.capabilities = capabilities
        self.onOpen = onOpen
        self.onClose = onClose
        self.onSkipForward = onSkipForward
        self.onSkipBackward = onSkipBackward
    }

    func stopMonitoring() {
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        localMonitor = nil
        globalMonitor = nil
        resetTracking()
    }
}

private extension NotchGestureMonitorView {
    func installMonitorsIfNeeded() {
        if localMonitor == nil {
            localMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                self?.handleScroll(event, screenLocation: self?.screenLocation(for: event))
                return event
            }
        }
        if globalMonitor == nil {
            globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                self?.handleScroll(event, screenLocation: NSEvent.mouseLocation)
            }
        }
    }

    func screenLocation(for event: NSEvent) -> NSPoint {
        if let window = event.window {
            return window.convertToScreen(NSRect(origin: event.locationInWindow, size: .zero)).origin
        }
        return NSEvent.mouseLocation
    }

    func handleScroll(_ event: NSEvent, screenLocation: NSPoint?) {
        guard AtelierSettings.gesturesEnabled else {
            resetTracking()
            return
        }
        guard event.hasPreciseScrollingDeltas else { return }
        guard let screenLocation, let screenRect = currentScreenRect() else { return }

        if event.phase.contains(.began) || event.phase.contains(.mayBegin) {
            isTracking = screenRect.contains(screenLocation)
            trackingState = NotchGestureTrackingState()
            return
        }

        guard isTracking else { return }

        if event.phase.contains(.ended) || event.phase.contains(.cancelled) {
            resetTracking()
            return
        }

        let delta = NotchGestureDelta(
            dx: CGFloat(event.scrollingDeltaX),
            dy: CGFloat(event.scrollingDeltaY),
            phase: .changed,
            isMomentum: !event.momentumPhase.isEmpty
        )

        let result = NotchGestureInterpreter.reduce(trackingState, delta: delta, capabilities: capabilities)
        trackingState = result.state

        switch result.action {
        case .open:
            DispatchQueue.main.async { [weak self] in self?.onOpen?() }
        case .close:
            DispatchQueue.main.async { [weak self] in self?.onClose?() }
        case .skipForward:
            DispatchQueue.main.async { [weak self] in self?.onSkipForward?() }
        case .skipBackward:
            DispatchQueue.main.async { [weak self] in self?.onSkipBackward?() }
        case nil:
            break
        }
    }

    func currentScreenRect() -> CGRect? {
        guard let window else { return nil }
        let rectInWindow = convert(bounds, to: nil)
        return window.convertToScreen(rectInWindow)
    }

    func resetTracking() {
        isTracking = false
        trackingState = NotchGestureTrackingState()
    }
}
