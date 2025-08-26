import AppKit
import Foundation
import HotKey

class GlobalHotkeyManager {
    private var volumeUpHotKey: HotKey?
    private var volumeDownHotKey: HotKey?
    private weak var connectionManager: MiloConnectionManager?
    private var isMonitoring = false
    
    init(connectionManager: MiloConnectionManager) {
        self.connectionManager = connectionManager
    }
    
    func startMonitoring() {
        guard AXIsProcessTrusted() else {
            requestAccessibilityPermissions()
            return
        }
        
        setupHotKeys()
        isMonitoring = true
    }
    
    func stopMonitoring() {
        volumeUpHotKey = nil
        volumeDownHotKey = nil
        isMonitoring = false
    }
    
    private func setupHotKeys() {
        volumeUpHotKey = nil
        volumeDownHotKey = nil
        
        volumeUpHotKey = HotKey(key: .upArrow, modifiers: [.option])
        volumeUpHotKey?.keyDownHandler = { [weak self] in
            self?.handleVolumeAdjustment(delta: 5, direction: "up")
        }
        
        volumeDownHotKey = HotKey(key: .downArrow, modifiers: [.option])
        volumeDownHotKey?.keyDownHandler = { [weak self] in
            self?.handleVolumeAdjustment(delta: -5, direction: "down")
        }
    }
    
    private func handleVolumeAdjustment(delta: Int, direction: String) {
        guard let connectionManager = connectionManager,
              connectionManager.isCurrentlyConnected(),
              let apiService = connectionManager.getAPIService() else {
            NSSound.beep()
            return
        }
        
        Task {
            do {
                try await apiService.adjustVolume(delta)
                await updateSliderAfterVolumeChange()
            } catch {
                await MainActor.run {
                    NSSound.beep()
                }
            }
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
    
    private func requestAccessibilityPermissions() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        
        let options: CFDictionary = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: true] as CFDictionary
        let result = AXIsProcessTrustedWithOptions(options)
        
        if result {
            setupHotKeys()
            isMonitoring = true
        } else {
            startPermissionMonitoring()
        }
    }
    
    private func startPermissionMonitoring() {
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            if AXIsProcessTrusted() {
                timer.invalidate()
                self?.setupHotKeys()
                self?.isMonitoring = true
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
        if AXIsProcessTrusted() && isMonitoring && (volumeUpHotKey == nil || volumeDownHotKey == nil) {
            setupHotKeys()
        }
    }
    
    deinit {
        stopMonitoring()
    }
}
