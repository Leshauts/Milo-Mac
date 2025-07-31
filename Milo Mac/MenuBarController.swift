import SwiftUI
import AppKit
import ServiceManagement

// MARK: - MenuBarController
class MenuBarController: NSObject, MiloConnectionManagerDelegate {
    private var statusItem: NSStatusItem
    
    // Un seul service de connexion
    private var connectionManager: MiloConnectionManager!
    
    // État simple
    private var isMiloConnected = false
    private var currentState: MiloState?
    private var currentVolume: VolumeStatus?
    
    // Interface utilisateur
    private var activeMenu: NSMenu?
    private var isPreferencesMenuActive = false
    private let volumeController = VolumeController()
    
    // Loading states
    private var loadingStates: [String: Bool] = [:]
    private var loadingTimers: [String: Timer] = [:]
    private var loadingStartTimes: [String: Date] = [:]
    private var loadingTarget: String?
    
    init(statusItem: NSStatusItem) {
        self.statusItem = statusItem
        super.init()
        
        setupStatusItem()
        setupConnectionManager()
        updateIcon()
    }
    
    private func setupStatusItem() {
        statusItem.button?.image = createCustomIcon()
        statusItem.button?.target = self
        statusItem.button?.action = #selector(menuButtonClicked)
        statusItem.button?.image?.isTemplate = true
    }
    
    private func createCustomIcon() -> NSImage? {
        if let image = NSImage(named: "menubar-icon") {
            image.isTemplate = true
            image.size = NSSize(width: 22, height: 22)
            return image
        }
        
        let fallbackImage = NSImage(systemSymbolName: "speaker.wave.3", accessibilityDescription: "Milo")
        fallbackImage?.isTemplate = true
        return fallbackImage
    }
    
    private func setupConnectionManager() {
        connectionManager = MiloConnectionManager()
        connectionManager.delegate = self
        connectionManager.start()
    }
    
    private func updateIcon() {
        DispatchQueue.main.async { [weak self] in
            self?.statusItem.button?.alphaValue = self?.isMiloConnected == true ? 1.0 : 0.5
        }
    }
    
    @objc private func menuButtonClicked() {
        statusItem.menu = nil
        
        guard let event = NSApp.currentEvent else {
            showMenu()
            return
        }
        
        let isOptionPressed = event.modifierFlags.contains(.option)
        
        if isOptionPressed {
            showPreferencesMenu()
        } else {
            showMenu()
        }
    }
    
    private func showMenu() {
        let menu = NSMenu()
        menu.font = NSFont.menuFont(ofSize: 13)
        
        if isMiloConnected {
            buildConnectedMenuWithLoading(menu)
        } else {
            buildDisconnectedMenu(menu)
        }
        
        activeMenu = menu
        isPreferencesMenuActive = false
        volumeController.activeMenu = menu
        
        displayMenu(menu)
    }
    
    private func showPreferencesMenu() {
        let menu = NSMenu()
        menu.font = NSFont.menuFont(ofSize: 13)
        
        if isMiloConnected {
            buildConnectedPreferencesMenu(menu)
        } else {
            buildDisconnectedPreferencesMenu(menu)
        }
        
        activeMenu = menu
        isPreferencesMenuActive = true
        
        displayMenu(menu)
    }
    
    private func displayMenu(_ menu: NSMenu) {
        NSApp.activate(ignoringOtherApps: true)
        
        statusItem.menu = menu
        
        if let button = statusItem.button {
            button.performClick(nil)
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.statusItem.menu = nil
            self?.monitorMenuClosure()
        }
    }
    
    // MARK: - Menu Building
    private func buildConnectedMenuWithLoading(_ menu: NSMenu) {
        // Volume
        let volumeItems = MenuItemFactory.createVolumeSection(
            volume: currentVolume?.volume ?? 50,
            target: self,
            action: #selector(volumeChanged)
        )
        volumeItems.forEach { menu.addItem($0) }
        
        if let sliderItem = volumeItems.first(where: { $0.view is MenuInteractionView }),
           let sliderView = sliderItem.view as? MenuInteractionView,
           let slider = sliderView.subviews.first(where: { $0 is NSSlider }) as? NSSlider {
            volumeController.setVolumeSlider(slider)
        }
        
        // Sources audio
        let sourceItems = MenuItemFactory.createAudioSourcesSectionWithLoading(
            state: currentState,
            loadingStates: loadingStates,
            loadingTarget: loadingTarget,
            target: self,
            action: #selector(sourceClickedWithLoading)
        )
        sourceItems.forEach { menu.addItem($0) }
        
        // Contrôles système
        let systemItems = MenuItemFactory.createSystemControlsSection(
            state: currentState,
            target: self,
            action: #selector(toggleClicked)
        )
        systemItems.forEach { menu.addItem($0) }
    }
    
    private func buildConnectedPreferencesMenu(_ menu: NSMenu) {
        buildConnectedMenuWithLoading(menu)
        
        // Section préférences
        menu.addItem(NSMenuItem.separator())
        
        // Toggle démarrage automatique
        let launchAtLoginItem = MenuItemHelper.createSimpleToggleItem(
            title: "Démarrer au démarrage du Mac",
            isEnabled: isLaunchAtLoginEnabled(),
            target: self,
            action: #selector(toggleLaunchAtLogin)
        )
        menu.addItem(launchAtLoginItem)
        
        // Quitter
        let quitItem = MenuItemHelper.createSimpleMenuItem(
            title: "Quitter",
            target: self,
            action: #selector(quitApplication)
        )
        menu.addItem(quitItem)
    }
    
    private func buildDisconnectedMenu(_ menu: NSMenu) {
        let disconnectedItem = MenuItemFactory.createDisconnectedItem()
        menu.addItem(disconnectedItem)
    }
    
    private func buildDisconnectedPreferencesMenu(_ menu: NSMenu) {
        buildDisconnectedMenu(menu)
        
        menu.addItem(NSMenuItem.separator())
        
        let launchAtLoginItem = MenuItemHelper.createSimpleToggleItem(
            title: "Démarrer au démarrage du Mac",
            isEnabled: isLaunchAtLoginEnabled(),
            target: self,
            action: #selector(toggleLaunchAtLogin)
        )
        menu.addItem(launchAtLoginItem)
        
        let quitItem = MenuItemHelper.createSimpleMenuItem(
            title: "Quitter",
            target: self,
            action: #selector(quitApplication)
        )
        menu.addItem(quitItem)
    }
    
    private func handleMenuClosed() {
        volumeController.forceSendPendingVolume()
        volumeController.cleanup()
        activeMenu = nil
        isPreferencesMenuActive = false
        volumeController.activeMenu = nil
    }
    
    private func monitorMenuClosure() {
        if let menu = activeMenu, menu.highlightedItem == nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                if self?.activeMenu?.highlightedItem == nil {
                    self?.handleMenuClosed()
                }
            }
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                self?.monitorMenuClosure()
            }
        }
    }
    
    // MARK: - Actions
    @objc private func sourceClickedWithLoading(_ sender: NSMenuItem) {
        guard let apiService = connectionManager.getAPIService() else {
            NSLog("❌ sourceClickedWithLoading: no API service available")
            return
        }
        guard let sourceId = sender.representedObject as? String else {
            NSLog("❌ sourceClickedWithLoading: invalid sourceId")
            return
        }
        
        NSLog("🎯 sourceClickedWithLoading: \(sourceId)")
        
        if loadingStates[sourceId] == true { return }
        
        let activeSource = currentState?.activeSource ?? "none"
        if activeSource == sourceId { return }
        
        loadingTarget = sourceId
        loadingStartTimes[sourceId] = Date()
        setLoadingState(for: sourceId, isLoading: true)
        
        loadingTimers[sourceId]?.invalidate()
        loadingTimers[sourceId] = Timer.scheduledTimer(withTimeInterval: 15.0, repeats: false) { _ in
            Task { @MainActor in
                self.stopLoadingForSource(sourceId)
            }
        }
        
        Task {
            do {
                NSLog("📡 Sending changeSource request for: \(sourceId)")
                try await apiService.changeSource(sourceId)
                NSLog("✅ changeSource request completed for: \(sourceId)")
            } catch {
                NSLog("❌ changeSource request failed for \(sourceId): \(error)")
                await MainActor.run {
                    self.stopLoadingForSource(sourceId)
                }
            }
        }
    }
    
    @objc private func toggleClicked(_ sender: NSMenuItem) {
        guard let apiService = connectionManager.getAPIService() else {
            NSLog("❌ toggleClicked: no API service available")
            return
        }
        guard let toggleType = sender.representedObject as? String else {
            NSLog("❌ toggleClicked: invalid toggleType")
            return
        }
        
        NSLog("🎯 toggleClicked: \(toggleType)")
        
        Task {
            do {
                switch toggleType {
                case "multiroom":
                    let newState = !(currentState?.multiroomEnabled ?? false)
                    NSLog("📡 Sending setMultiroom request: \(newState)")
                    try await apiService.setMultiroom(newState)
                    NSLog("✅ setMultiroom request completed: \(newState)")
                case "equalizer":
                    let newState = !(currentState?.equalizerEnabled ?? false)
                    NSLog("📡 Sending setEqualizer request: \(newState)")
                    try await apiService.setEqualizer(newState)
                    NSLog("✅ setEqualizer request completed: \(newState)")
                default:
                    NSLog("❌ Unknown toggle type: \(toggleType)")
                    break
                }
            } catch {
                NSLog("❌ Toggle request failed for \(toggleType): \(error)")
            }
        }
    }
    
    @objc private func volumeChanged(_ sender: NSSlider) {
        let newVolume = Int(sender.doubleValue)
        volumeController.handleVolumeChange(newVolume)
    }
    
    @objc private func toggleLaunchAtLogin() {
        if #available(macOS 13.0, *) {
            let service = SMAppService.mainApp
            
            do {
                if service.status == .enabled {
                    try service.unregister()
                } else {
                    try service.register()
                }
            } catch {
                print("❌ Erreur toggle démarrage: \(error)")
            }
        } else {
            let bundleIdentifier = Bundle.main.bundleIdentifier ?? ""
            let currentStatus = isLaunchAtLoginEnabled()
            SMLoginItemSetEnabled(bundleIdentifier as CFString, !currentStatus)
        }
    }
    
    @objc private func quitApplication() {
        NSApplication.shared.terminate(nil)
    }
    
    // MARK: - Utilities
    private func isLaunchAtLoginEnabled() -> Bool {
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        } else {
            let bundleIdentifier = Bundle.main.bundleIdentifier ?? ""
            return SMLoginItemSetEnabled(bundleIdentifier as CFString, false)
        }
    }
    
    // MARK: - Loading State Management
    private func setLoadingState(for sourceId: String, isLoading: Bool) {
        if loadingStates[sourceId] == isLoading { return }
        
        let oldState = loadingStates[sourceId] ?? false
        loadingStates[sourceId] = isLoading
        
        if let menu = activeMenu, oldState != isLoading {
            updateMenuInRealTime(menu)
        }
    }
    
    private func stopLoadingForSource(_ sourceId: String) {
        setLoadingState(for: sourceId, isLoading: false)
        loadingTimers[sourceId]?.invalidate()
        loadingTimers[sourceId] = nil
        loadingStartTimes[sourceId] = nil
        
        if loadingTarget == sourceId {
            loadingTarget = nil
        }
    }
    
    private func updateMenuInRealTime(_ menu: NSMenu) {
        CircularMenuItem.cleanupAllSpinners()
        
        menu.removeAllItems()
        
        if isMiloConnected {
            if isPreferencesMenuActive {
                buildConnectedPreferencesMenu(menu)
            } else {
                buildConnectedMenuWithLoading(menu)
            }
        } else {
            if isPreferencesMenuActive {
                buildDisconnectedPreferencesMenu(menu)
            } else {
                buildDisconnectedMenu(menu)
            }
        }
    }
}

// MARK: - MiloConnectionManagerDelegate
extension MenuBarController {
    func miloDidConnect() {
        NSLog("🎉 Milo connected - updating UI")
        
        isMiloConnected = true
        updateIcon()
        
        // Configurer le volume controller avec l'API service
        if let apiService = connectionManager.getAPIService() {
            volumeController.apiService = apiService
        }
        
        // Rafraîchir l'état initial
        Task {
            await refreshState()
            await refreshVolumeStatus()
        }
    }
    
    func miloDidDisconnect() {
        NSLog("💔 Milo disconnected - updating UI")
        
        isMiloConnected = false
        updateIcon()
        
        // Nettoyer les états
        currentState = nil
        currentVolume = nil
        volumeController.apiService = nil
        
        // Arrêter tous les loadings
        for (sourceId, _) in loadingStates {
            loadingStates[sourceId] = false
            loadingTimers[sourceId]?.invalidate()
            loadingTimers[sourceId] = nil
            loadingStartTimes[sourceId] = nil
        }
        loadingTarget = nil
        
        volumeController.cleanup()
        
        // Rafraîchir le menu si ouvert
        if let menu = activeMenu {
            updateMenuInRealTime(menu)
        }
    }
    
    func didReceiveStateUpdate(_ state: MiloState) {
        currentState = state
        
        // Gérer les loadings terminés
        if !state.isTransitioning {
            for (sourceId, isLoading) in loadingStates {
                if isLoading && state.activeSource == sourceId {
                    let startTime = loadingStartTimes[sourceId] ?? Date()
                    let elapsed = Date().timeIntervalSince(startTime)
                    let minimumDuration: TimeInterval = 1.0
                    
                    if elapsed >= minimumDuration {
                        stopLoadingForSource(sourceId)
                    } else {
                        let remainingTime = minimumDuration - elapsed
                        DispatchQueue.main.asyncAfter(deadline: .now() + remainingTime) { [weak self] in
                            self?.stopLoadingForSource(sourceId)
                        }
                    }
                }
            }
        }
        
        // Rafraîchir le menu si nécessaire
        let hasActiveLoading = loadingStates.values.contains(true)
        if let menu = activeMenu, !hasActiveLoading {
            updateMenuInRealTime(menu)
        }
    }
    
    func didReceiveVolumeUpdate(_ volume: VolumeStatus) {
        currentVolume = volume
        volumeController.setCurrentVolume(volume)
        volumeController.updateSliderFromWebSocket(volume.volume)
    }
    
    // MARK: - State Refresh
    private func refreshState() async {
        guard let apiService = connectionManager.getAPIService() else { return }
        
        do {
            let state = try await apiService.fetchState()
            await MainActor.run {
                self.currentState = state
                NSLog("📊 State refreshed: \(state.activeSource)")
            }
        } catch {
            NSLog("❌ Erreur refresh état: \(error)")
        }
    }
    
    private func refreshVolumeStatus() async {
        guard let apiService = connectionManager.getAPIService() else { return }
        
        do {
            let volumeStatus = try await apiService.getVolumeStatus()
            await MainActor.run {
                self.currentVolume = volumeStatus
                self.volumeController.setCurrentVolume(volumeStatus)
                NSLog("🔊 Volume refreshed: \(volumeStatus.volume)")
            }
        } catch {
            NSLog("❌ Erreur refresh volume: \(error)")
        }
    }
}
