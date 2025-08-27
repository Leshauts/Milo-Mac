import AppKit
import Foundation
import HotKey

class GlobalHotkeyManager {
    private var volumeUpHotKey: HotKey?
    private var volumeDownHotKey: HotKey?
    private weak var connectionManager: MiloConnectionManager?
    private weak var menuController: MenuBarController?
    private var isMonitoring = false
    
    // NOUVEAU: Instance de VolumeHUD
    private var volumeHUD: VolumeHUD?
    
    init(connectionManager: MiloConnectionManager, menuController: MenuBarController) {
        self.connectionManager = connectionManager
        self.menuController = menuController
        
        // NOUVEAU: Initialiser le VolumeHUD
        self.volumeHUD = VolumeHUD()
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
        // Vérifier si le menu est ouvert avant de traiter le raccourci
        if let menuController = menuController, menuController.isMenuCurrentlyOpen() {
            NSSound.beep()
            return
        }
        
        guard let connectionManager = connectionManager,
              connectionManager.isCurrentlyConnected(),
              let apiService = connectionManager.getAPIService() else {
            NSSound.beep()
            return
        }
        
        Task {
            do {
                try await apiService.adjustVolume(delta)
                
                // NOUVEAU: Récupérer le volume mis à jour et afficher la HUD
                await updateVolumeHUDAfterChange()
                
                // Conserver l'ancienne logique pour le slider du menu
                await updateSliderAfterVolumeChange()
            } catch {
                await MainActor.run {
                    NSSound.beep()
                }
            }
        }
    }
    
    // NOUVEAU: Méthode pour mettre à jour la VolumeHUD
    @MainActor
    private func updateVolumeHUDAfterChange() async {
        guard let apiService = connectionManager?.getAPIService(),
              let volumeHUD = volumeHUD else { return }
        
        do {
            let volumeStatus = try await apiService.getVolumeStatus()
            
            // Afficher la HUD avec le volume mis à jour
            volumeHUD.show(volume: volumeStatus.volume)
            
        } catch {
            // En cas d'erreur, on peut essayer d'estimer le volume
            // ou simplement ignorer l'affichage de la HUD
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
