import AppKit
import Foundation

class VolumeController {
    weak var apiService: MiloAPIService?
    weak var activeMenu: NSMenu?
    
    private var pendingVolume: Int?
    private var lastVolumeAPICall: Date?
    private var volumeDebounceWorkItem: DispatchWorkItem?
    private var isUserInteracting = false
    private var lastUserInteraction: Date?
    private var volumeSlider: NSSlider?
    private var currentVolume: VolumeStatus?
    
    private let volumeDebounceDelay: TimeInterval = 0.03
    private let volumeImmediateSendThreshold: TimeInterval = 0.1
    private let userInteractionTimeout: TimeInterval = 0.3
    
    func setCurrentVolume(_ volume: VolumeStatus) {
        self.currentVolume = volume
    }
    
    func setVolumeSlider(_ slider: NSSlider) {
        self.volumeSlider = slider
    }
    
    func handleVolumeChange(_ newVolume: Int) {
        isUserInteracting = true
        lastUserInteraction = Date()
        pendingVolume = newVolume
        
        let now = Date()
        let shouldSendImmediately = lastVolumeAPICall == nil ||
                                  now.timeIntervalSince(lastVolumeAPICall!) > volumeImmediateSendThreshold
        
        if shouldSendImmediately {
            sendVolumeUpdate(newVolume)
        } else {
            scheduleDelayedVolumeUpdate()
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + userInteractionTimeout) { [weak self] in
            guard let self = self, let lastInteraction = self.lastUserInteraction else { return }
            
            if Date().timeIntervalSince(lastInteraction) >= self.userInteractionTimeout {
                self.isUserInteracting = false
            }
        }
    }
    
    func updateSliderFromWebSocket(_ volume: Int) {
        guard let slider = volumeSlider, !isUserInteracting else { return }
        
        // Éviter les mises à jour inutiles
        if Int(slider.doubleValue) == volume {
            return
        }
        
        // Désactiver temporairement l'action pour éviter les boucles
        let originalTarget = slider.target
        let originalAction = slider.action
        slider.target = nil
        slider.action = nil
        
        slider.doubleValue = Double(volume)
        
        // Forcer la mise à jour visuelle du slider custom
        if let nativeSlider = slider as? NativeVolumeSlider {
            nativeSlider.needsDisplay = true
        }
        
        slider.target = originalTarget
        slider.action = originalAction
    }
    
    func forceSendPendingVolume() {
        if let pendingVol = pendingVolume {
            sendVolumeUpdate(pendingVol)
        }
    }
    
    // CORRECTION : Cleanup moins agressif pour éviter les race conditions
    func cleanup() {
       // NSLog("🧹 VolumeController cleanup - preserving critical state")
        
        // CHANGEMENT : Ne pas supprimer volumeSlider immédiatement
        // Il sera remplacé par le nouveau setVolumeSlider() du nouveau menu
        
        // Nettoyer seulement les timers et états temporaires
        lastUserInteraction = nil
        isUserInteracting = false
        volumeDebounceWorkItem?.cancel()
        volumeDebounceWorkItem = nil
        
        // GARDE : Conserver pendingVolume, lastVolumeAPICall, volumeSlider et currentVolume
        // pour éviter la perte de données lors de réouvertures rapides
    }
    
    // CORRECTION : Vérifications renforcées avant envoi API
    private func sendVolumeUpdate(_ volume: Int) {
        // AJOUT : Vérifications plus robustes
        guard let apiService = apiService else {
            NSLog("⚠️ Cannot send volume - no API service")
            return
        }
        
        // CHANGEMENT : Vérifier activeMenu OU volumeSlider (pas forcément les deux)
        guard activeMenu != nil || volumeSlider != nil else {
            NSLog("⚠️ Cannot send volume - no active menu or slider")
            return
        }
        
        lastVolumeAPICall = Date()
        NSLog("📡 Sending volume to API: \(volume)%")
        
        Task { @MainActor in
            do {
                try await apiService.setVolume(volume)
                NSLog("✅ Volume set to \(volume)%")
                // Clear pending volume en cas de succès
                if self.pendingVolume == volume {
                    self.pendingVolume = nil
                }
            } catch {
                // Garder la valeur en pending si échec
                NSLog("❌ Volume API failed: \(error.localizedDescription)")
                self.pendingVolume = volume  // Sera envoyé au prochain refresh ou force send
            }
        }
    }
    
    private func scheduleDelayedVolumeUpdate() {
        volumeDebounceWorkItem?.cancel()
        
        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self, let volume = self.pendingVolume else { return }
            // CHANGEMENT : Vérification plus souple
            guard self.activeMenu != nil || self.volumeSlider != nil else {
                NSLog("⚠️ Skipping delayed volume update - no active context")
                return
            }
            self.sendVolumeUpdate(volume)
        }
        
        volumeDebounceWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + volumeDebounceDelay, execute: workItem)
    }
}
