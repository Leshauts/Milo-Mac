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
        
        let originalTarget = slider.target
        let originalAction = slider.action
        slider.target = nil
        slider.action = nil
        
        slider.doubleValue = Double(volume)
        
        slider.target = originalTarget
        slider.action = originalAction
    }
    
    func forceSendPendingVolume() {
        if let pendingVol = pendingVolume {
            sendVolumeUpdate(pendingVol)
        }
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
    
    private func sendVolumeUpdate(_ volume: Int) {
        guard activeMenu != nil else { return }
        lastVolumeAPICall = Date()
        
        Task { @MainActor in
            do {
                try await apiService?.setVolume(volume)
            } catch {
                print("❌ Erreur volume: \(error)")
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
        DispatchQueue.main.asyncAfter(deadline: .now() + volumeDebounceDelay, execute: workItem)
    }
}
