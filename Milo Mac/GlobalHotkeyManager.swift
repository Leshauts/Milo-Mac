import AppKit
import Foundation

class GlobalHotkeyManager {
    private weak var connectionManager: MiloConnectionManager?
    private weak var menuController: MenuBarController?
    private var isMonitoring = false
    
    // Instance de VolumeHUD
    private var volumeHUD: VolumeHUD?
    
    // Variables pour le hold-to-repeat
    private var repeatTimer: Timer?
    private var currentRepeatDirection: String?
    private var currentRepeatDelta: Int = 0
    
    // Event monitors
    private var flagsChangedMonitor: Any?
    private var eventTap: CFMachPort?
    
    // État des touches
    private var isRightOptionPressed = false
    private var isUpArrowPressed = false
    private var isDownArrowPressed = false
    
    // Configuration du timing
    private let initialRepeatDelay: TimeInterval = 0.5
    private let repeatInterval: TimeInterval = 0.08
    
    // Key codes
    private let upArrowKeyCode: UInt16 = 126
    private let downArrowKeyCode: UInt16 = 125
    
    // Flags pour Option droite
    private let rightOptionMask: UInt = 0x40
    
    init(connectionManager: MiloConnectionManager, menuController: MenuBarController) {
        self.connectionManager = connectionManager
        self.menuController = menuController
        self.volumeHUD = VolumeHUD()
    }
    
    func startMonitoring() {
        guard AXIsProcessTrusted() else {
            requestAccessibilityPermissions()
            return
        }
        
        isMonitoring = true
        setupEventMonitoring()
        setupEventTap()
    }
    
    func stopMonitoring() {
        stopCurrentRepeat()
        isMonitoring = false
        removeEventMonitors()
    }
    
    private func setupEventMonitoring() {
        // Nettoyer l'ancien monitor s'il existe
        if let monitor = flagsChangedMonitor {
            NSEvent.removeMonitor(monitor)
            flagsChangedMonitor = nil
        }
        
        // Créer le nouveau monitor
        flagsChangedMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged]) { [weak self] event in
            self?.handleFlagsChanged(event)
        }
    }
    
    private func setupEventTap() {
        // Nettoyer l'ancien event tap s'il existe
        cleanupEventTap()
        
        guard AXIsProcessTrusted() else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                guard let self = self, self.isMonitoring else { return }
                self.setupEventTap()
            }
            return
        }
        
        let eventMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
        
        guard let eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                let manager = Unmanaged<GlobalHotkeyManager>.fromOpaque(refcon!).takeUnretainedValue()
                return manager.handleCGEvent(proxy: proxy, type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            return
        }
        
        self.eventTap = eventTap
        
        let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
    }
    
    private func handleCGEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        guard isMonitoring else {
            return Unmanaged.passUnretained(event)
        }
        
        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        
        if keyCode == upArrowKeyCode || keyCode == downArrowKeyCode {
            if type == .keyDown {
                handleArrowKeyDown(keyCode: keyCode)
            } else if type == .keyUp {
                handleArrowKeyUp(keyCode: keyCode)
            }
            
            // Si Option droite est enfoncé, intercepter l'événement
            if isRightOptionPressed {
                return nil
            }
        }
        
        return Unmanaged.passUnretained(event)
    }
    
    private func handleArrowKeyDown(keyCode: UInt16) {
        switch keyCode {
        case upArrowKeyCode:
            isUpArrowPressed = true
            checkForVolumeAction(direction: "up", delta: 5)
            
        case downArrowKeyCode:
            isDownArrowPressed = true
            checkForVolumeAction(direction: "down", delta: -5)
            
        default:
            break
        }
    }
    
    private func handleArrowKeyUp(keyCode: UInt16) {
        switch keyCode {
        case upArrowKeyCode:
            isUpArrowPressed = false
            if currentRepeatDirection == "up" {
                stopCurrentRepeat()
            }
            
        case downArrowKeyCode:
            isDownArrowPressed = false
            if currentRepeatDirection == "down" {
                stopCurrentRepeat()
            }
            
        default:
            break
        }
    }
    
    private func handleFlagsChanged(_ event: NSEvent) {
        guard isMonitoring else { return }
        
        let eventFlags = UInt(event.modifierFlags.rawValue)
        let wasRightOptionPressed = isRightOptionPressed
        isRightOptionPressed = (eventFlags & rightOptionMask) != 0
        
        if wasRightOptionPressed && !isRightOptionPressed {
            stopCurrentRepeat()
        }
    }
    
    private func checkForVolumeAction(direction: String, delta: Int) {
        guard isRightOptionPressed else { return }
        
        if let menuController = menuController, menuController.isMenuCurrentlyOpen() {
            NSSound.beep()
            return
        }
        
        guard let connectionManager = connectionManager,
              connectionManager.isCurrentlyConnected(),
              connectionManager.getAPIService() != nil else {
            NSSound.beep()
            return
        }
        
        if let currentDirection = currentRepeatDirection, currentDirection != direction {
            stopCurrentRepeat()
        }
        
        if currentRepeatDirection != direction {
            executeVolumeChange(delta: delta, direction: direction)
            
            currentRepeatDirection = direction
            currentRepeatDelta = delta
            
            repeatTimer = Timer.scheduledTimer(withTimeInterval: initialRepeatDelay, repeats: false) { [weak self] _ in
                self?.startContinuousRepeat()
            }
        }
    }
    
    private func startContinuousRepeat() {
        guard let direction = currentRepeatDirection else { return }
        
        repeatTimer = Timer.scheduledTimer(withTimeInterval: repeatInterval, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            
            let shouldContinue = self.isRightOptionPressed &&
                               ((direction == "up" && self.isUpArrowPressed) ||
                                (direction == "down" && self.isDownArrowPressed))
            
            if shouldContinue {
                self.executeVolumeChange(delta: self.currentRepeatDelta, direction: direction)
            } else {
                self.stopCurrentRepeat()
            }
        }
    }
    
    private func stopCurrentRepeat() {
        repeatTimer?.invalidate()
        repeatTimer = nil
        currentRepeatDirection = nil
        currentRepeatDelta = 0
    }
    
    private func executeVolumeChange(delta: Int, direction: String) {
        guard let connectionManager = connectionManager,
              connectionManager.isCurrentlyConnected() else {
            stopCurrentRepeat()
            return
        }
        
        Task {
            do {
                guard let apiService = connectionManager.getAPIService() else {
                    await MainActor.run { self.stopCurrentRepeat() }
                    return
                }
                try await apiService.adjustVolume(delta)
                await updateVolumeHUDAfterChange()
                await updateSliderAfterVolumeChange()
            } catch {
                await MainActor.run {
                    NSSound.beep()
                    self.stopCurrentRepeat()
                }
            }
        }
    }
    
    @MainActor
    private func updateVolumeHUDAfterChange() async {
        guard let apiService = connectionManager?.getAPIService(),
              let volumeHUD = volumeHUD else { return }
        
        do {
            let volumeStatus = try await apiService.getVolumeStatus()
            volumeHUD.show(volume: volumeStatus.volume)
        } catch {
            NSLog("Erreur lors de la récupération du volume pour la HUD: \(error)")
        }
    }
    
    @MainActor
    private func updateSliderAfterVolumeChange() async {
        guard let apiService = connectionManager?.getAPIService() else { return }
        
        do {
            let volumeStatus = try await apiService.getVolumeStatus()
            NotificationCenter.default.post(
                name: NSNotification.Name("VolumeChangedViaHotkey"),
                object: volumeStatus
            )
        } catch {
            // Ignore errors silently
        }
    }
    
    private func cleanupEventTap() {
        if let eventTap = eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            CFMachPortInvalidate(eventTap)
            self.eventTap = nil
        }
    }
    
    private func removeEventMonitors() {
        if let monitor = flagsChangedMonitor {
            NSEvent.removeMonitor(monitor)
            flagsChangedMonitor = nil
        }
        
        cleanupEventTap()
    }
    
    private func requestAccessibilityPermissions() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        
        let options: CFDictionary = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: true] as CFDictionary
        let result = AXIsProcessTrustedWithOptions(options)
        
        if result {
            isMonitoring = true
            setupEventMonitoring()
            setupEventTap()
        } else {
            startPermissionMonitoring()
        }
    }
    
    private func startPermissionMonitoring() {
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            if AXIsProcessTrusted() {
                timer.invalidate()
                self?.isMonitoring = true
                self?.setupEventMonitoring()
                self?.setupEventTap()
            }
        }
    }
    
    func isCurrentlyMonitoring() -> Bool {
        return isMonitoring
    }
    
    func hasAccessibilityPermissions() -> Bool {
        return AXIsProcessTrusted()
    }
    
    func recheckPermissions() {
        if AXIsProcessTrusted() {
            if !isMonitoring {
                isMonitoring = true
            }
            setupEventMonitoring()
            setupEventTap()
        }
    }
    
    deinit {
        stopCurrentRepeat()
        removeEventMonitors()
    }
}
