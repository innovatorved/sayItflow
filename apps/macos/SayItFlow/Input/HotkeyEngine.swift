import ApplicationServices
import AppKit
import Carbon
import Foundation
import KeyboardShortcuts

enum HotkeyEvent: Sendable, Equatable {
    case pressStarted
    case pressEnded
}

/// CGEventTap runs on a dedicated thread; Carbon hotkeys and local NSEvent monitors run on main.
final class HotkeyEngine: @unchecked Sendable {
    private let handler: @Sendable (HotkeyEvent) -> Void
    private let onTapFailed: @Sendable (String) -> Void
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var tapThread: Thread?
    private var tapRunLoop: CFRunLoop?
    private let stateLock = NSLock()
    private var isKeyDown = false
    private var mode: HotkeyMode = .holdSpace
    private var shouldRun = false
    private var localKeyDownMonitor: Any?
    private var localKeyUpMonitor: Any?
    private var localFlagsMonitor: Any?
    private var holdSpaceLogic = HoldSpaceKeyLogic()
    private var holdActivationWorkItem: DispatchWorkItem?
    private let timerQueue = DispatchQueue(label: "SayItFlow.HoldSpaceTimer", qos: .userInteractive)

    private var carbonEventHandlerRef: EventHandlerRef?
    private var carbonSpaceHotKeyRef: EventHotKeyRef?
    private var isCarbonSpaceModeEnabled = false
    private var isCustomShortcutEnabled = false
    private var spaceReRegisterWorkItem: DispatchWorkItem?

    private static let spaceKeyCode: Int64 = 49
    private static let carbonSpaceSignature: OSType = 0x5349_4648 // "SIFH"
    private static let carbonSpaceHotKeyID: UInt32 = 1

    init(
        handler: @escaping @Sendable (HotkeyEvent) -> Void,
        onTapFailed: @escaping @Sendable (String) -> Void = { _ in }
    ) {
        self.handler = handler
        self.onTapFailed = onTapFailed
        performOnMain { [weak self] in
            KeyboardShortcuts.disable(.pushToTalk)
            KeyboardShortcuts.onKeyDown(for: .pushToTalk) { [weak self] in
                guard let self else { return }
                self.stateLock.lock()
                let active = self.shouldRun && self.mode == .custom
                self.stateLock.unlock()
                if active {
                    _ = self.beginPress()
                }
            }
            KeyboardShortcuts.onKeyUp(for: .pushToTalk) { [weak self] in
                guard let self else { return }
                self.stateLock.lock()
                let active = self.shouldRun && self.mode == .custom
                self.stateLock.unlock()
                if active {
                    _ = self.endPress()
                }
            }
        }
    }

    /// True only when the initial Space press was passed through to the target app before the 0.25s threshold.
    /// When Carbon RegisterEventHotKey is active, WindowServer swallows the initial Space press, so no Backspace is needed.
    var didPassThroughInitialSpace: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return !isCarbonSpaceModeEnabled
    }

    func updateMode(_ mode: HotkeyMode) {
        stateLock.lock()
        let previousMode = self.mode
        self.mode = mode
        stateLock.unlock()

        if previousMode != mode {
            performOnMain { [weak self] in
                guard let self else { return }
                self.clearSpaceHoldState()
                _ = self.endPress()
                self.syncCarbonHotkeysOnMain()
            }
        } else {
            performOnMain { [weak self] in
                self?.syncCarbonHotkeysOnMain()
            }
        }
    }

    var hasLiveTap: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return eventTap != nil
    }

    /// True when the tap exists and is enabled (not disabled by timeout or user input).
    var tapIsHealthy: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard let tap = eventTap else { return false }
        return CGEvent.tapIsEnabled(tap: tap)
    }

    func start() {
        stateLock.lock()
        if tapThread != nil, eventTap != nil {
            shouldRun = true
            stateLock.unlock()
            performOnMain { [weak self] in
                self?.syncCarbonHotkeysOnMain()
            }
            return
        }
        if tapThread != nil {
            stateLock.unlock()
            stop()
            stateLock.lock()
        }
        shouldRun = true
        stateLock.unlock()

        performOnMain { [weak self] in
            self?.installLocalMonitors()
            self?.syncCarbonHotkeysOnMain()
        }

        let thread = Thread { [weak self] in
            self?.runTapLoop()
        }
        thread.name = "SayItFlow.HotkeyEngine"
        thread.start()

        stateLock.lock()
        tapThread = thread
        stateLock.unlock()
    }

    func stop() {
        stateLock.lock()
        shouldRun = false
        let thread = tapThread
        let runLoop = tapRunLoop
        stateLock.unlock()

        performOnMain { [weak self] in
            self?.removeLocalMonitors()
            self?.syncCarbonHotkeysOnMain()
        }

        if let runLoop {
            CFRunLoopPerformBlock(runLoop, CFRunLoopMode.defaultMode.rawValue) {
                if let source = self.runLoopSource {
                    CFRunLoopSourceInvalidate(source)
                }
                if let tap = self.eventTap {
                    CGEvent.tapEnable(tap: tap, enable: false)
                }
                self.stateLock.lock()
                self.runLoopSource = nil
                self.eventTap = nil
                self.stateLock.unlock()
                CFRunLoopStop(runLoop)
            }
            CFRunLoopWakeUp(runLoop)
        }

        thread?.cancel()
        while thread?.isExecuting == true {
            Thread.sleep(forTimeInterval: 0.01)
        }

        performOnMain { [weak self] in
            self?.clearSpaceHoldState()
        }

        stateLock.lock()
        tapThread = nil
        tapRunLoop = nil
        isKeyDown = false
        stateLock.unlock()
    }

    // MARK: - Carbon Hotkeys (Hold Space & Custom Combo)

    private func syncCarbonHotkeysOnMain() {
        stateLock.lock()
        let running = shouldRun
        let currentMode = mode
        stateLock.unlock()

        let enableCustom = (running && currentMode == .custom)
        if enableCustom {
            KeyboardShortcuts.enable(.pushToTalk)
        } else {
            KeyboardShortcuts.disable(.pushToTalk)
        }
        stateLock.lock()
        isCustomShortcutEnabled = enableCustom
        stateLock.unlock()

        if running && currentMode == .holdSpace {
            installCarbonEventHandlerIfNeeded()
            registerCarbonSpaceHotKey()
            stateLock.lock()
            isCarbonSpaceModeEnabled = (carbonSpaceHotKeyRef != nil)
            stateLock.unlock()
        } else {
            spaceReRegisterWorkItem?.cancel()
            spaceReRegisterWorkItem = nil
            unregisterCarbonSpaceHotKey()
            stateLock.lock()
            isCarbonSpaceModeEnabled = false
            stateLock.unlock()
        }
    }

    private func installCarbonEventHandlerIfNeeded() {
        guard carbonEventHandlerRef == nil else { return }
        var eventTypes = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
        ]
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData -> OSStatus in
                guard let event, let userData else { return OSStatus(eventNotHandledErr) }
                let engine = Unmanaged<HotkeyEngine>.fromOpaque(userData).takeUnretainedValue()
                return engine.handleCarbonHotKeyEvent(event)
            },
            eventTypes.count,
            &eventTypes,
            selfPtr,
            &carbonEventHandlerRef
        )
    }

    private func registerCarbonSpaceHotKey() {
        guard carbonSpaceHotKeyRef == nil else { return }
        let hotKeyID = EventHotKeyID(signature: Self.carbonSpaceSignature, id: Self.carbonSpaceHotKeyID)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(kVK_Space),
            0,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &ref
        )
        if status == noErr {
            carbonSpaceHotKeyRef = ref
        }
    }

    private func unregisterCarbonSpaceHotKey() {
        if let ref = carbonSpaceHotKeyRef {
            UnregisterEventHotKey(ref)
            carbonSpaceHotKeyRef = nil
        }
    }

    private func handleCarbonHotKeyEvent(_ event: EventRef) -> OSStatus {
        var hotKeyID = EventHotKeyID()
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID
        )
        guard status == noErr,
              hotKeyID.signature == Self.carbonSpaceSignature,
              hotKeyID.id == Self.carbonSpaceHotKeyID else {
            return OSStatus(eventNotHandledErr)
        }

        stateLock.lock()
        let active = shouldRun && mode == .holdSpace
        stateLock.unlock()
        guard active else { return noErr }

        let kind = GetEventKind(event)
        if kind == UInt32(kEventHotKeyPressed) {
            _ = handleHoldSpaceKeyDown(isRepeat: false)
        } else if kind == UInt32(kEventHotKeyReleased) {
            let result = handleHoldSpaceKeyUp()
            if !result.consume && !result.endDictation {
                emitQuickTapSpaceOnMain()
            }
        }
        return noErr
    }

    private func emitQuickTapSpaceOnMain() {
        spaceReRegisterWorkItem?.cancel()
        spaceReRegisterWorkItem = nil
        unregisterCarbonSpaceHotKey()
        MainActor.assumeIsolated {
            _ = KeystrokeEmitter.postSpace()
        }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.stateLock.lock()
            let active = self.shouldRun && self.mode == .holdSpace
            self.stateLock.unlock()
            if active {
                self.registerCarbonSpaceHotKey()
            }
        }
        spaceReRegisterWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.012, execute: work)
    }

    // MARK: - Local monitor (in-app text fields, selects, etc.)

    private func performOnMain(_ work: () -> Void) {
        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.sync(execute: work)
        }
    }

    private func installLocalMonitors() {
        removeLocalMonitors()
        localKeyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleLocalEvent(event) ?? event
        }
        localKeyUpMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyUp) { [weak self] event in
            self?.handleLocalEvent(event) ?? event
        }
        localFlagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleLocalEvent(event) ?? event
        }
    }

    private func removeLocalMonitors() {
        if let localKeyDownMonitor {
            NSEvent.removeMonitor(localKeyDownMonitor)
            self.localKeyDownMonitor = nil
        }
        if let localKeyUpMonitor {
            NSEvent.removeMonitor(localKeyUpMonitor)
            self.localKeyUpMonitor = nil
        }
        if let localFlagsMonitor {
            NSEvent.removeMonitor(localFlagsMonitor)
            self.localFlagsMonitor = nil
        }
    }

    private func handleLocalEvent(_ event: NSEvent) -> NSEvent? {
        if KeystrokeEmitter.isSimulated(event) {
            return event
        }
        stateLock.lock()
        let currentMode = mode
        let carbonSpaceActive = isCarbonSpaceModeEnabled
        let customActive = isCustomShortcutEnabled
        stateLock.unlock()

        let consume: Bool
        switch currentMode {
        case .holdSpace:
            if carbonSpaceActive { return event }
            consume = handleLocalHoldSpace(event)
        case .fnKey:
            if tapIsHealthy { return event }
            consume = handleLocalFnKey(event)
        case .rightOption:
            if tapIsHealthy { return event }
            consume = handleLocalRightOption(event)
        case .custom:
            if customActive { return event }
            consume = handleLocalCustomCombo(event)
        }
        return consume ? nil : event
    }

    private func handleLocalHoldSpace(_ event: NSEvent) -> Bool {
        guard event.keyCode == Self.spaceKeyCode else { return false }
        if event.modifierFlags.intersection([.command, .option, .control]).isEmpty == false {
            return false
        }
        switch event.type {
        case .keyDown:
            return handleHoldSpaceKeyDown(isRepeat: event.isARepeat)
        case .keyUp:
            let result = handleHoldSpaceKeyUp()
            return result.consume
        default:
            return false
        }
    }

    private func handleLocalFnKey(_ event: NSEvent) -> Bool {
        guard event.type == .flagsChanged else { return false }
        let fnDown = event.modifierFlags.contains(.function)
        if fnDown {
            return beginPress()
        }
        return endPress()
    }

    private func handleLocalRightOption(_ event: NSEvent) -> Bool {
        guard event.type == .flagsChanged, event.keyCode == 61 else { return false }
        let optionDown = event.modifierFlags.contains(.option)
        if optionDown {
            return beginPress()
        }
        return endPress()
    }

    private func handleLocalCustomCombo(_ event: NSEvent) -> Bool {
        guard let shortcut = KeyboardShortcuts.getShortcut(for: .pushToTalk),
              let key = shortcut.key else {
            return false
        }
        let required = nsFlags(from: shortcut.carbonModifiers)
        let flags = event.modifierFlags
        let modifiersMatch = required.isSubset(of: flags) || flags.contains(required)
        let keyMatch = Int(key.rawValue) == Int(event.keyCode)

        switch event.type {
        case .keyDown where modifiersMatch && keyMatch:
            if event.isARepeat {
                stateLock.lock()
                let held = isKeyDown
                stateLock.unlock()
                return held
            }
            return beginPress()
        case .keyUp where keyMatch:
            return endPress()
        case .flagsChanged where !required.isEmpty && !modifiersMatch:
            endPress()
            return false
        default:
            return false
        }
    }

    // MARK: - Global tap

    private func runTapLoop() {
        defer {
            stateLock.lock()
            if let source = runLoopSource {
                CFRunLoopSourceInvalidate(source)
                runLoopSource = nil
            }
            if let currentTap = eventTap {
                CGEvent.tapEnable(tap: currentTap, enable: false)
                eventTap = nil
            }
            tapRunLoop = nil
            if tapThread === Thread.current {
                tapThread = nil
            }
            stateLock.unlock()
        }

        let mask = (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)
            | (1 << CGEventType.tapDisabledByTimeout.rawValue)
            | (1 << CGEventType.tapDisabledByUserInput.rawValue)

        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let engine = Unmanaged<HotkeyEngine>.fromOpaque(refcon).takeUnretainedValue()
            return engine.handleEvent(type: type, event: event)
        }
        let userInfo = Unmanaged.passUnretained(self).toOpaque()

        let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: callback,
            userInfo: userInfo
        ) ?? CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(mask),
            callback: callback,
            userInfo: userInfo
        )

        guard let tap else {
            stateLock.lock()
            shouldRun = false
            stateLock.unlock()
            onTapFailed(
                "Could not create global hotkey listener. Enable Accessibility and Input Monitoring for SayItFlow in System Settings."
            )
            return
        }

        stateLock.lock()
        eventTap = tap
        tapRunLoop = CFRunLoopGetCurrent()
        stateLock.unlock()

        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        if let source = runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        }
        CGEvent.tapEnable(tap: tap, enable: true)

        while true {
            CFRunLoopRunInMode(.defaultMode, 0.25, false)
            stateLock.lock()
            let stillRunning = shouldRun
            if let currentTap = eventTap, stillRunning, !CGEvent.tapIsEnabled(tap: currentTap) {
                CGEvent.tapEnable(tap: currentTap, enable: true)
            }
            stateLock.unlock()
            if !stillRunning { break }
        }
    }

    private func handleEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            stateLock.lock()
            let tap = eventTap
            stateLock.unlock()
            if let tap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        if event.getIntegerValueField(.eventSourceUserData) == KeystrokeEmitter.simulatedEventTag {
            return Unmanaged.passUnretained(event)
        }

        stateLock.lock()
        let currentMode = mode
        let carbonSpaceActive = isCarbonSpaceModeEnabled
        stateLock.unlock()

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags

        switch currentMode {
        case .holdSpace:
            if carbonSpaceActive {
                return Unmanaged.passUnretained(event)
            }
            return handleHoldSpace(type: type, keyCode: keyCode, flags: flags, event: event)
        case .fnKey:
            return handleFnKey(type: type, flags: flags, event: event)
        case .rightOption:
            return handleRightOption(type: type, flags: flags, event: event)
        case .custom:
            return Unmanaged.passUnretained(event)
        }
    }

    private func handleHoldSpace(
        type: CGEventType,
        keyCode: Int64,
        flags: CGEventFlags,
        event: CGEvent
    ) -> Unmanaged<CGEvent>? {
        guard keyCode == Self.spaceKeyCode else {
            return Unmanaged.passUnretained(event)
        }
        if flags.contains(.maskCommand) || flags.contains(.maskAlternate)
            || flags.contains(.maskControl) {
            return Unmanaged.passUnretained(event)
        }

        switch type {
        case .keyDown:
            let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
            return consumeIf(handleHoldSpaceKeyDown(isRepeat: isRepeat), event: event)
        case .keyUp:
            let result = handleHoldSpaceKeyUp()
            return result.consume ? nil : Unmanaged.passUnretained(event)
        default:
            return Unmanaged.passUnretained(event)
        }
    }

    // MARK: - Hold Space threshold (passthrough first press, consume repeats, activate after 0.25s)

    private func handleHoldSpaceKeyDown(isRepeat: Bool) -> Bool {
        stateLock.lock()
        let wasDown = holdSpaceLogic.spaceDownAt != nil
        let isDictating = isKeyDown || holdSpaceLogic.holdActivated
        let consume = holdSpaceLogic.keyDown(isRepeat: isRepeat, isDictating: isDictating)
        let shouldSchedule = !wasDown && holdSpaceLogic.spaceDownAt != nil && !isDictating
        let shouldActivateNow: Bool
        if let downAt = holdSpaceLogic.spaceDownAt,
           !isDictating,
           CFAbsoluteTimeGetCurrent() - downAt >= HoldSpaceKeyLogic.holdThresholdSeconds,
           holdSpaceLogic.thresholdElapsed(isDictating: isKeyDown) {
            isKeyDown = true
            shouldActivateNow = true
        } else {
            shouldActivateNow = false
        }
        stateLock.unlock()

        if shouldActivateNow {
            cancelSpaceHoldTimer()
            handler(.pressStarted)
        } else if shouldSchedule {
            scheduleSpaceHoldActivation()
        }
        return consume
    }

    private func handleHoldSpaceKeyUp() -> HoldSpaceKeyLogic.KeyUpResult {
        cancelSpaceHoldTimer()
        stateLock.lock()
        let result = holdSpaceLogic.keyUp(isDictating: isKeyDown)
        stateLock.unlock()
        if result.endDictation {
            _ = endPress()
        }
        return result
    }

    private func scheduleSpaceHoldActivation() {
        stateLock.lock()
        holdActivationWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.activateSpaceHoldIfStillDown()
        }
        holdActivationWorkItem = item
        stateLock.unlock()

        timerQueue.asyncAfter(
            deadline: .now() + HoldSpaceKeyLogic.holdThresholdSeconds,
            execute: item
        )
    }

    private func activateSpaceHoldIfStillDown() {
        // Threshold flip and isKeyDown must happen under one lock or key-up races the tap thread.
        stateLock.lock()
        guard holdSpaceLogic.thresholdElapsed(isDictating: isKeyDown), !isKeyDown else {
            stateLock.unlock()
            return
        }
        isKeyDown = true
        stateLock.unlock()
        handler(.pressStarted)
    }

    private func cancelSpaceHoldTimer() {
        stateLock.lock()
        holdActivationWorkItem?.cancel()
        holdActivationWorkItem = nil
        stateLock.unlock()
    }

    private func clearSpaceHoldState() {
        stateLock.lock()
        holdActivationWorkItem?.cancel()
        holdActivationWorkItem = nil
        holdSpaceLogic.reset()
        stateLock.unlock()
    }

    private func handleFnKey(type: CGEventType, flags: CGEventFlags, event: CGEvent) -> Unmanaged<CGEvent>? {
        guard type == .flagsChanged else { return Unmanaged.passUnretained(event) }
        let fnDown = flags.contains(.maskSecondaryFn)
        if fnDown {
            _ = beginPress()
        } else {
            _ = endPress()
        }
        // listenOnly: always pass through modifier events
        return Unmanaged.passUnretained(event)
    }

    private func handleRightOption(type: CGEventType, flags: CGEventFlags, event: CGEvent) -> Unmanaged<CGEvent>? {
        guard type == .flagsChanged else { return Unmanaged.passUnretained(event) }
        guard event.getIntegerValueField(.keyboardEventKeycode) == 61 else {
            return Unmanaged.passUnretained(event)
        }
        let optionDown = flags.contains(.maskAlternate)
        if optionDown {
            _ = beginPress()
        } else {
            _ = endPress()
        }
        // listenOnly: always pass through modifier events
        return Unmanaged.passUnretained(event)
    }

    private func handleCustomCombo(
        type: CGEventType,
        keyCode: Int64,
        flags: CGEventFlags,
        event: CGEvent
    ) -> Unmanaged<CGEvent>? {
        guard let shortcut = KeyboardShortcuts.getShortcut(for: .pushToTalk),
              let key = shortcut.key else {
            return Unmanaged.passUnretained(event)
        }

        let required = carbonFlags(from: shortcut.carbonModifiers)
        let modifiersMatch = required.isSubset(of: flags) || flags.contains(required)
        let keyMatch = Int64(key.rawValue) == keyCode

        switch type {
        case .keyDown where modifiersMatch && keyMatch:
            let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
            if isRepeat {
                stateLock.lock()
                let held = isKeyDown
                stateLock.unlock()
                return held ? nil : Unmanaged.passUnretained(event)
            }
            return consumeIf(beginPress(), event: event)
        case .keyUp where keyMatch:
            return consumeIf(endPress(), event: event)
        case .flagsChanged where !required.isEmpty && !modifiersMatch:
            // Releasing the modifier before the key would otherwise leave isKeyDown
            // latched with no matching pressEnded, so dictation never stops.
            endPress()
            return Unmanaged.passUnretained(event)
        default:
            return Unmanaged.passUnretained(event)
        }
    }

    @discardableResult
    private func beginPress() -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard !isKeyDown else { return true }
        isKeyDown = true
        handler(.pressStarted)
        return true
    }

    @discardableResult
    private func endPress() -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard isKeyDown else { return false }
        isKeyDown = false
        handler(.pressEnded)
        return true
    }

    private func consumeIf(_ consume: Bool, event: CGEvent) -> Unmanaged<CGEvent>? {
        consume ? nil : Unmanaged.passUnretained(event)
    }

    private func carbonFlags(from modifiers: Int) -> CGEventFlags {
        var flags = CGEventFlags()
        if modifiers & cmdKey != 0 { flags.insert(.maskCommand) }
        if modifiers & optionKey != 0 { flags.insert(.maskAlternate) }
        if modifiers & controlKey != 0 { flags.insert(.maskControl) }
        if modifiers & shiftKey != 0 { flags.insert(.maskShift) }
        return flags
    }

    private func nsFlags(from modifiers: Int) -> NSEvent.ModifierFlags {
        var flags = NSEvent.ModifierFlags()
        if modifiers & cmdKey != 0 { flags.insert(.command) }
        if modifiers & optionKey != 0 { flags.insert(.option) }
        if modifiers & controlKey != 0 { flags.insert(.control) }
        if modifiers & shiftKey != 0 { flags.insert(.shift) }
        return flags
    }
}
