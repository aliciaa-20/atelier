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
    /// See `NotchGestureInterpreter.reduce`'s own doc comment -- `nil`
    /// keeps the notch panel's on-device-tuned defaults.
    var threshold: CGFloat? = nil
    var dominanceMultiplier: CGFloat? = nil
    let onOpen: () -> Void
    let onClose: () -> Void
    let onSkipForward: () -> Void
    let onSkipBackward: () -> Void
    /// Only used when `capabilities.canScrub` -- streams the gesture's
    /// total horizontal distance, then signals when the finger lifts.
    var onScrub: ((CGFloat) -> Void)? = nil
    var onScrubEnded: (() -> Void)? = nil

    func body(content: Content) -> some View {
        content.background(
            NotchGestureMonitorRepresentable(
                capabilities: capabilities,
                threshold: threshold,
                dominanceMultiplier: dominanceMultiplier,
                onOpen: onOpen,
                onClose: onClose,
                onSkipForward: onSkipForward,
                onSkipBackward: onSkipBackward,
                onScrub: onScrub,
                onScrubEnded: onScrubEnded
            )
        )
    }
}

private struct NotchGestureMonitorRepresentable: NSViewRepresentable {
    let capabilities: NotchGestureCapabilities
    let threshold: CGFloat?
    let dominanceMultiplier: CGFloat?
    let onOpen: () -> Void
    let onClose: () -> Void
    let onSkipForward: () -> Void
    let onSkipBackward: () -> Void
    let onScrub: ((CGFloat) -> Void)?
    let onScrubEnded: (() -> Void)?

    func makeNSView(context: Context) -> NotchGestureMonitorView {
        let view = NotchGestureMonitorView()
        view.update(
            capabilities: capabilities,
            threshold: threshold,
            dominanceMultiplier: dominanceMultiplier,
            onOpen: onOpen,
            onClose: onClose,
            onSkipForward: onSkipForward,
            onSkipBackward: onSkipBackward,
            onScrub: onScrub,
            onScrubEnded: onScrubEnded
        )
        return view
    }

    func updateNSView(_ nsView: NotchGestureMonitorView, context: Context) {
        nsView.update(
            capabilities: capabilities,
            threshold: threshold,
            dominanceMultiplier: dominanceMultiplier,
            onOpen: onOpen,
            onClose: onClose,
            onSkipForward: onSkipForward,
            onSkipBackward: onSkipBackward,
            onScrub: onScrub,
            onScrubEnded: onScrubEnded
        )
    }

    static func dismantleNSView(_ nsView: NotchGestureMonitorView, coordinator: ()) {
        nsView.stopMonitoring()
    }
}

@MainActor private final class NotchGestureMonitorView: NSView {
    private var localMonitor: Any?
    private var globalMonitor: Any?

    private var capabilities = NotchGestureCapabilities(canOpen: false, canClose: false, canSkip: false)
    private var threshold: CGFloat?
    private var dominanceMultiplier: CGFloat?
    private var onOpen: (() -> Void)?
    private var onClose: (() -> Void)?
    private var onSkipForward: (() -> Void)?
    private var onSkipBackward: (() -> Void)?
    private var onScrub: ((CGFloat) -> Void)?
    private var onScrubEnded: (() -> Void)?

    private var trackingState = NotchGestureTrackingState()
    private var isTracking = false
    private var isScrubbing = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        installMonitorsIfNeeded()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    isolated deinit {
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        installMonitorsIfNeeded()
    }

    func update(
        capabilities: NotchGestureCapabilities,
        threshold: CGFloat?,
        dominanceMultiplier: CGFloat?,
        onOpen: @escaping () -> Void,
        onClose: @escaping () -> Void,
        onSkipForward: @escaping () -> Void,
        onSkipBackward: @escaping () -> Void,
        onScrub: ((CGFloat) -> Void)?,
        onScrubEnded: (() -> Void)?
    ) {
        self.capabilities = capabilities
        self.threshold = threshold
        self.dominanceMultiplier = dominanceMultiplier
        self.onOpen = onOpen
        self.onClose = onClose
        self.onSkipForward = onSkipForward
        self.onSkipBackward = onSkipBackward
        self.onScrub = onScrub
        self.onScrubEnded = onScrubEnded
    }

    func stopMonitoring() {
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        localMonitor = nil
        globalMonitor = nil
        resetTracking()
    }

    /// This view exists purely to install `NSEvent` monitors — the
    /// monitors fire regardless of AppKit hit-testing, so it has no
    /// business intercepting clicks meant for the SwiftUI content above
    /// it. Same class of concern as `ClickThroughHostingView` (ADR 0004).
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
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
            endScrubIfNeeded()
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

        let result = NotchGestureInterpreter.reduce(
            trackingState,
            delta: delta,
            capabilities: capabilities,
            threshold: threshold ?? NotchGestureInterpreter.threshold,
            dominanceMultiplier: dominanceMultiplier ?? NotchGestureInterpreter.dominanceMultiplier
        )
        trackingState = result.state

        // `NSEvent` monitor callbacks (both local and global) already run
        // on the main thread, so dispatching here only added a run-loop
        // turn of latency to a feature whose whole point is feel.
        switch result.action {
        case .open:
            onOpen?()
        case .close:
            onClose?()
        case .skipForward:
            onSkipForward?()
        case .skipBackward:
            onSkipBackward?()
        case .scrub(let totalDX):
            isScrubbing = true
            onScrub?(totalDX)
        case nil:
            break
        }
    }

    func currentScreenRect() -> CGRect? {
        guard let window else { return nil }
        let rectInWindow = convert(bounds, to: nil)
        return window.convertToScreen(rectInWindow)
    }

    func endScrubIfNeeded() {
        guard isScrubbing else { return }
        isScrubbing = false
        onScrubEnded?()
    }

    func resetTracking() {
        endScrubIfNeeded()
        isTracking = false
        trackingState = NotchGestureTrackingState()
    }
}
