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
    
    func cleanup() {
        // Nettoyer les états temporaires
        lastUserInteraction = nil
        isUserInteracting = false
        volumeDebounceWorkItem?.cancel()
        volumeDebounceWorkItem = nil
    }
    
    private func sendVolumeUpdate(_ volume: Int) {
        guard let apiService = apiService else { return }
        guard activeMenu != nil || volumeSlider != nil else { return }
        
        lastVolumeAPICall = Date()
        
        Task {
            do {
                try await apiService.setVolume(volume)
                // Clear pending volume en cas de succès
                if self.pendingVolume == volume {
                    self.pendingVolume = nil
                }
            } catch {
                // Garder la valeur en pending si échec
                self.pendingVolume = volume
            }
        }
    }
    
    private func scheduleDelayedVolumeUpdate() {
        volumeDebounceWorkItem?.cancel()
        
        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self, let volume = self.pendingVolume else { return }
            guard self.activeMenu != nil || self.volumeSlider != nil else { return }
            self.sendVolumeUpdate(volume)
        }
        
        volumeDebounceWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + volumeDebounceDelay, execute: workItem)
    }
}
