import AppKit
import Carbon.HIToolbox
import MetalKit
import ScreenCaptureKit

/// Orchestrates sensor -> capture -> renderer -> overlay for the desktop
/// bend effect. State-machine shape ported from IuCC123/BendMac's
/// `AppModel.swift` (MIT) -- reconnect-on-failure, capture only starts once
/// actually bending -- minus the Settings-window/menu-bar/Sparkle-updater
/// concerns that file mixed in, which stay in Atelier's own conventional
/// places (`BendEffectPane`, `AtelierSettings`, the app-wide `LaunchAtLogin`).
@MainActor
final class BendEffectController: ObservableObject {
    static let shared = BendEffectController()

    @Published private(set) var wantsEnabled: Bool {
        didSet {
            AtelierSettings.bendEffectEnabled = wantsEnabled
            updateSensorSuspension()
        }
    }
    @Published private(set) var enabled = false
    @Published private(set) var starting = false
    @Published private(set) var status = "Ready to preview. Enable to bend your desktop."
    @Published private(set) var sensorAngle: Double?
    @Published var previewAngle = 105.0
    @Published var previewPlaying = false
    @Published var previewFollowsLid = false

    let frames = FrameStore()
    let previewFrames = FrameStore()
    let sensor = LidSensor()
    lazy var capture = DesktopCapture(frames: frames)
    private var overlay: BendEffectOverlayWindow?
    private var renderer: BendRenderer?

    // `deinit` runs nonisolated regardless of actor; these four are only
    // ever touched on the main actor otherwise -- same `LockScreenManager`/
    // `LidSensor` convention this codebase already uses for that gap.
    private nonisolated(unsafe) var timer: Timer?
    private nonisolated(unsafe) var hotKey: EventHotKeyRef?
    private nonisolated(unsafe) var handler: EventHandlerRef?
    private var generation = 0
    private var stopping = false
    private var sleeping = false
    private var needsUserAction = false
    private var reconnectTask: Task<Void, Never>?
    private static let hotKeySignature: OSType = 0x41544C42  // 'ATLB' -- distinct from GlobalHotkeys' 'ATLR'
    private var progress = 0.0
    private var lastTime = CACurrentMediaTime()
    private var playStart = 0.0
    private var wasFolded = false

    private nonisolated(unsafe) var observers: [(NotificationCenter, NSObjectProtocol)] = []
    /// Reference count of live viewers of `sensorAngle` (the Settings
    /// pane's Lid Behavior/Preview sections) -- see `updateSensorSuspension`.
    private var paneObserverCount = 0

    private init() {
        wantsEnabled = AtelierSettings.bendEffectEnabled
        sensor.onAngle = { [weak self] angle in
            guard let self, !self.sleeping else { return }
            guard self.sensorAngle != angle else { return }
            let becameAvailable = self.sensorAngle == nil && angle != nil
            self.sensorAngle = angle
            if self.enabled || self.starting || becameAvailable { self.settingsChanged() }
        }
        sensor.start()
        // Off by default: don't poll the HID sensor every 250ms for a
        // feature nobody has turned on, per CLAUDE.md's "default pollers to
        // idle/off when their output isn't currently visible or needed".
        // Resumed by `enable()`/a restored `wantsEnabled`, or while the
        // Settings pane has the Lid Behavior/Preview sections open.
        updateSensorSuspension()
        capture.onError = { [weak self] error in
            guard let self else { return }
            if Self.requiresUserAction(error) {
                self.disable(message: "Screen capture stopped. Enable the bend effect again when you are ready.")
            } else {
                self.interrupt(message: "Capture interrupted: \(error.localizedDescription)")
            }
        }
        capture.onFirstFrame = { [weak self] in
            if self?.enabled == true { self?.startTicking() }
        }
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        observers.append((workspaceCenter, workspaceCenter.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.sleeping = true
                self.sensor.setSuspended(true)
                self.interrupt(message: "Paused until your Mac wakes.")
            }
        }))
        observers.append((workspaceCenter, workspaceCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.sleeping = false
                self.sensorAngle = nil
                self.updateSensorSuspension()
                self.sensor.reconnect()
                self.scheduleReconnect()
            }
        }))
        observers.append((NotificationCenter.default, NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                if self?.wantsEnabled == true {
                    self?.interrupt(message: "Reconnecting to your display…")
                }
            }
        }))
        observers.append((NotificationCenter.default, NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.settingsChanged() }
        }))
        scheduleReconnect()
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, context in
                guard let context else { return OSStatus(eventNotHandledErr) }
                var hotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                    nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID
                )
                // Carbon delivers every kEventHotKeyPressed event to the most
                // recently installed handler first; returning noErr for a
                // signature that isn't ours would swallow GlobalHotkeys'
                // Teleprompter shortcuts before they ever see the event.
                guard status == noErr, hotKeyID.signature == BendEffectController.hotKeySignature else {
                    return status == noErr ? OSStatus(eventNotHandledErr) : status
                }
                let controller = Unmanaged<BendEffectController>.fromOpaque(context).takeUnretainedValue()
                MainActor.assumeIsolated { controller.disable(message: "Paused with Escape.") }
                return noErr
            }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handler)
    }

    deinit {
        reconnectTask?.cancel()
        timer?.invalidate()
        for (center, observer) in observers { center.removeObserver(observer) }
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
    }

    func parameters(preview: Bool = false) -> BendParameters {
        var p = BendParameters()
        p.progress = Float(
            preview ? BendMath.progress(angle: displayedPreviewAngle, clearAngle: AtelierSettings.bendEffectClearAngle) : progress)
        p.perspective = Float(AtelierSettings.bendEffectPerspective)
        p.blur = Float(AtelierSettings.bendEffectBlur)
        p.shadow = Float(AtelierSettings.bendEffectShadow)
        p.style = Float(AtelierSettings.bendEffectStyle)
        return p
    }

    var displayedPreviewAngle: Double {
        previewFollowsLid ? (sensorAngle ?? AtelierSettings.bendEffectClearAngle) : previewAngle
    }

    func calibrateOpenAngle() {
        guard let sensorAngle else { return }
        AtelierSettings.bendEffectClearAngle = min(135, max(80, sensorAngle))
    }

    func resetAppearance() {
        AtelierSettings.bendEffectPerspective = 1
        AtelierSettings.bendEffectBlur = 0.9
        AtelierSettings.bendEffectShadow = 0.35
        AtelierSettings.bendEffectStyle = 0
    }

    func enable() {
        needsUserAction = false
        wantsEnabled = true
        scheduleReconnect(immediate: true)
    }

    func disable(message: String = "Paused. Your desktop is back to normal.", preserveIntent: Bool = false) {
        stopEffect(message: message, preserveIntent: preserveIntent, keepReady: false)
    }

    func playPreview() {
        previewFollowsLid = false
        playStart = CACurrentMediaTime()
        previewPlaying = true
        startTicking()
    }

    /// Called from `BendEffectPane`'s `onAppear`/`onDisappear` -- the pane
    /// shows a live `sensorAngle` reading (Lid Behavior, "Use live lid
    /// angle") even while the effect itself is off, so the sensor needs to
    /// keep polling while that UI is on screen.
    func beginObservingSensor() {
        paneObserverCount += 1
        updateSensorSuspension()
    }

    func endObservingSensor() {
        paneObserverCount = max(0, paneObserverCount - 1)
        updateSensorSuspension()
    }

    private func updateSensorSuspension() {
        sensor.setSuspended(!(wantsEnabled || paneObserverCount > 0))
    }

    // Match the visibility threshold so imperceptible lid jitter never starts capture.
    private var targetProgress: Double {
        let angle = AtelierSettings.bendEffectFollowLid ? (sensorAngle ?? AtelierSettings.bendEffectClearAngle) : AtelierSettings.bendEffectManualAngle
        let target = BendMath.progress(angle: angle, clearAngle: AtelierSettings.bendEffectClearAngle)
        return target > 0.0005 ? target : 0
    }

    private var readyStatus: String { "Ready. Screen capture is off until the desktop bends." }

    private func settingsChanged() {
        let followLid = AtelierSettings.bendEffectFollowLid
        if followLid && sensorAngle == nil && (enabled || starting) {
            interrupt(message: "Waiting for the lid sensor… Turn off Follow lid to use a manual angle.")
        } else if starting && targetProgress == 0 {
            // Opening during SCStream startup must drain that attempt before another can begin.
            stopEffect(message: readyStatus, preserveIntent: true, keepReady: true)
        } else if enabled {
            if overlay != nil {
                startTicking()
            } else {
                sensor.setMode(followLid ? .watching : .idle)
                scheduleReconnect(immediate: true)
            }
        } else if wantsEnabled {
            scheduleReconnect(immediate: true)
        }
    }

    private enum ConnectionResult { case connected, retry, needsAttention }

    private static func requiresUserAction(_ error: Error) -> Bool {
        let error = error as NSError
        return error.domain == SCStreamErrorDomain
            && [
                SCStreamError.Code.userDeclined.rawValue,
                SCStreamError.Code.userStopped.rawValue,
                SCStreamError.Code.missingEntitlements.rawValue,
            ].contains(error.code)
    }

    /// One complete attempt, including asynchronous capture startup and cleanup.
    private func connect(generation request: Int) async -> ConnectionResult {
        let followLid = AtelierSettings.bendEffectFollowLid
        guard !followLid || sensorAngle != nil else {
            status = "Waiting for the lid sensor… Turn off Follow lid to use a manual angle."
            sensor.reconnect()
            return .retry
        }
        guard
            let screen = NSScreen.screens.first(where: {
                CGDisplayIsBuiltin(
                    ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
                        ?? 0
                ) != 0
            }),
            let displayID = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?
                .uint32Value
        else {
            status = "Connect the built-in display to use the desktop effect."
            return .retry
        }
        // Enabling arms the lid sensor. An open desktop must have no capture session:
        // even a hidden, low-frame-rate stream can blank protected video in other apps.
        guard targetProgress > 0 else {
            enabled = true
            starting = false
            sensor.setMode(followLid ? .watching : .idle)
            status = readyStatus
            return .connected
        }
        enabled = false
        starting = true
        sensor.setMode(followLid ? .active : .idle)
        status = "Connecting to your desktop…"
        var captureAttempted = false
        do {
            let renderer = try BendRenderer(frames: frames)
            renderer.parameters = { [weak self] in self?.parameters() ?? BendParameters() }
            let window = BendEffectOverlayWindow(screenFrame: screen.frame, renderer: renderer)
            self.renderer = renderer
            overlay = window
            // Register the hidden overlay before querying shareable content, including at login.
            captureAttempted = true
            try await capture.start(displayID: displayID)
            guard generation == request, !Task.isCancelled else { return .needsAttention }
            enabled = true
            starting = false
            progress = 0
            startTicking()
            status =
                followLid
                ? "Live desktop connected. Close the lid gently to bend it."
                : "Live desktop connected. Use the manual angle to bend it."
            return .connected
        } catch {
            guard generation == request, !Task.isCancelled else { return .needsAttention }
            await capture.stop()
            guard generation == request, !Task.isCancelled else { return .needsAttention }
            clearOverlay()
            starting = false
            if Self.requiresUserAction(error) {
                status =
                    "Allow the bend effect in System Settings → Privacy & Security → Screen & System Audio Recording, then try again."
                return .needsAttention
            }
            status = "Could not connect: \(error.localizedDescription)"
            // Hardware/Metal initialization errors need attention; capture can recover after login or wake.
            return captureAttempted ? .retry : .needsAttention
        }
    }
    private func interrupt(message: String) {
        guard wantsEnabled else { return }
        disable(message: message, preserveIntent: true)
    }
    private func scheduleReconnect(immediate: Bool = false) {
        guard reconnectTask == nil, wantsEnabled, !enabled || (overlay == nil && targetProgress > 0),
            !starting, !stopping, !sleeping, !needsUserAction
        else { return }
        generation += 1
        let request = generation
        reconnectTask = Task { [weak self] in
            defer {
                if self?.generation == request { self?.reconnectTask = nil }
            }
            // Await the actual result; a temporary capture failure consumes an attempt, not the whole loop.
            for attempt in 0..<15 {
                if attempt > 0 || !immediate {
                    do { try await Task.sleep(for: .seconds(1)) } catch { return }
                }
                guard let self, self.generation == request, self.wantsEnabled,
                    !self.sleeping, !Task.isCancelled
                else { return }
                switch await self.connect(generation: request) {
                case .connected: return
                case .needsAttention:
                    if self.generation == request { self.needsUserAction = true }
                    return
                case .retry: break
                }
            }
            if let self, self.generation == request {
                self.status += " Try connecting again."
            }
        }
    }
    private func clearOverlay() {
        overlay?.hide()
        overlay = nil
        renderer = nil
        if let hotKey {
            UnregisterEventHotKey(hotKey)
            self.hotKey = nil
        }
    }
    private func stopEffect(message: String, preserveIntent: Bool, keepReady: Bool) {
        if !preserveIntent { wantsEnabled = false }
        let pendingConnection = reconnectTask
        pendingConnection?.cancel()
        reconnectTask = nil
        generation += 1
        enabled = keepReady
        progress = 0
        wasFolded = false
        sensor.setMode(keepReady && AtelierSettings.bendEffectFollowLid ? .watching : .idle)
        clearOverlay()
        if !previewPlaying { stopTicking() }
        status = message
        guard !stopping else { return }
        stopping = true
        Task {
            await capture.stop()
            // A canceled start may still be inside ScreenCaptureKit. Drain it before opening another stream.
            await pendingConnection?.value
            stopping = false
            starting = false
            scheduleReconnect(immediate: enabled)
        }
    }
    private func stopTicking() {
        timer?.invalidate()
        timer = nil
    }
    /// Sensor/input changes restart smoothing; a settled effect needs no model timer.
    private func startTicking() {
        guard timer == nil else { return }
        lastTime = CACurrentMediaTime()
        let timer = Timer(timeInterval: 1 / 60.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }
    private func tick() {
        guard enabled || previewPlaying else {
            stopTicking()
            return
        }
        let now = CACurrentMediaTime()
        let dt = now - lastTime
        lastTime = now
        if previewPlaying {
            let clearAngle = AtelierSettings.bendEffectClearAngle
            let t = (now - playStart) / 4.2
            if t >= 1 {
                previewPlaying = false
                previewAngle = clearAngle
            } else {
                previewAngle = clearAngle - (clearAngle - 18) * pow(sin(t * .pi), 2)
            }
        }
        guard enabled, overlay != nil else {
            if !previewPlaying { stopTicking() }
            return
        }
        let target = targetProgress
        let hasFrame = frames.hasFrame
        // Capture startup can return before ScreenCaptureKit delivers its first frame.
        // Keep the undrawn overlay aligned with the real desktop instead of letting the
        // fold advance invisibly and then appearing partway through the animation.
        progress =
            !hasFrame
            ? 0
            : NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
                ? target : BendMath.smooth(current: progress, target: target, dt: dt)
        let followLid = AtelierSettings.bendEffectFollowLid
        sensor.setMode(!followLid ? .idle : (target > 0 || progress > 0 ? .active : .watching))
        let visible = progress > 0.0005 && hasFrame
        if visible && overlay?.isVisible == false {
            overlay?.show()
            Task { await capture.setBending(true) }
            RegisterEventHotKey(
                UInt32(kVK_Escape), 0, EventHotKeyID(signature: BendEffectController.hotKeySignature, id: 1),
                GetApplicationEventTarget(), 0, &hotKey)
        } else if !visible && overlay?.isVisible == true {
            overlay?.hide()
            Task { await capture.setBending(false) }
            if let hotKey {
                UnregisterEventHotKey(hotKey)
                self.hotKey = nil
            }
        }
        if !previewPlaying && progress == target { stopTicking() }
        if progress > 0.15 { wasFolded = true }
        if target == 0 && progress <= 0.0005 && wasFolded {
            wasFolded = false
            if AtelierSettings.bendEffectSound { NSSound(named: "Tink")?.play() }
        }
        if target == 0 && progress <= 0.0005 {
            // Hiding the overlay or lowering FPS is insufficient: release SCStream too.
            stopEffect(message: readyStatus, preserveIntent: true, keepReady: true)
        }
    }
}
