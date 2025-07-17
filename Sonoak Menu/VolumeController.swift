import AppKit
import Foundation

// MARK: - Volume Controller
class VolumeController {
    weak var apiService: OakOSAPIService?
    weak var activeMenu: NSMenu?
    
    private var pendingVolume: Int?
    private var lastVolumeAPICall: Date?
    private var volumeDebounceWorkItem: DispatchWorkItem?
    private var isUserInteracting = false
    private var lastUserInteraction: Date?
    private var volumeSlider: NSSlider?
    private var currentVolume: VolumeStatus?
    
    // MARK: - Constants
    private struct Constants {
        static let volumeDebounceDelay: TimeInterval = 0.03
        static let volumeImmediateSendThreshold: TimeInterval = 0.1
        static let userInteractionTimeout: TimeInterval = 0.3
    }
    
    // MARK: - Public Methods
    func setCurrentVolume(_ volume: VolumeStatus) {
        self.currentVolume = volume
    }
    
    func setVolumeSlider(_ slider: NSSlider) {
        self.volumeSlider = slider
    }
    
    func handleVolumeChange(_ newVolume: Int) {
        // Marquer l'interaction utilisateur
        isUserInteracting = true
        lastUserInteraction = Date()
        
        // Stocker la valeur cible
        pendingVolume = newVolume
        
        // Décider si on envoie immédiatement ou on débounce
        let now = Date()
        let shouldSendImmediately = lastVolumeAPICall == nil ||
                                  now.timeIntervalSince(lastVolumeAPICall!) > Constants.volumeImmediateSendThreshold
        
        if shouldSendImmediately {
            sendVolumeUpdate(newVolume)
        } else {
            scheduleDelayedVolumeUpdate()
        }
        
        // Arrêter l'interaction après un délai
        DispatchQueue.main.asyncAfter(deadline: .now() + Constants.userInteractionTimeout) { [weak self] in
            guard let self = self, let lastInteraction = self.lastUserInteraction else { return }
            
            if Date().timeIntervalSince(lastInteraction) >= Constants.userInteractionTimeout {
                self.isUserInteracting = false
            }
        }
    }
    
    func updateSliderFromWebSocket(_ volume: Int) {
        guard let slider = volumeSlider, !isUserInteracting else { return }
        
        // Désactiver temporairement l'action pour éviter la boucle
        let originalTarget = slider.target
        let originalAction = slider.action
        slider.target = nil
        slider.action = nil
        
        // Mettre à jour la valeur
        slider.doubleValue = Double(volume)
        
        // Forcer le redraw pour notre slider personnalisé
        if let nativeSlider = slider as? NativeVolumeSlider {
            nativeSlider.needsDisplay = true
        }
        
        // Restaurer l'action immédiatement
        slider.target = originalTarget
        slider.action = originalAction
    }
    
    func cleanup() {
        pendingVolume = nil
        lastVolumeAPICall = nil
        lastUserInteraction = nil
        isUserInteracting = false
        volumeSlider = nil
        
        volumeDebounceWorkItem?.cancel()
        volumeDebounceWorkItem = nil
    }
    
    func forceSendPendingVolume() {
        if let pendingVol = pendingVolume {
            sendVolumeUpdate(pendingVol)
        }
    }
    
    // MARK: - Private Methods
    private func sendVolumeUpdate(_ volume: Int) {
        guard activeMenu != nil else { return }
        
        lastVolumeAPICall = Date()
        
        Task { @MainActor in
            do {
                try await apiService?.setVolume(volume)
            } catch {
                print("❌ Erreur changement volume: \(error)")
            }
        }
    }
    
    private func scheduleDelayedVolumeUpdate() {
        volumeDebounceWorkItem?.cancel()
        
        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self, let volume = self.pendingVolume else { return }
            guard self.activeMenu != nil else { return }
            
            self.sendVolumeUpdate(volume)
        }
        
        volumeDebounceWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + Constants.volumeDebounceDelay, execute: workItem)
    }
}
