import SwiftUI
import AppKit
import ServiceManagement

// MARK: - MenuBarController
class MenuBarController: NSObject, MiloConnectionManagerDelegate {
    private var statusItem: NSStatusItem
    
    // Un seul service de connexion
    private var connectionManager: MiloConnectionManager!
    
    // Gestionnaire des raccourcis globaux
    private var hotkeyManager: GlobalHotkeyManager?
    
    // État simple
    private var isMiloConnected = false
    private var currentState: MiloState?
    private var currentVolume: VolumeStatus?
    private var isMenuOpen = false  // NOUVEAU: Flag pour bloquer les raccourcis
    
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
        setupHotkeyVolumeObserver()
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
        
        // Initialiser le gestionnaire des raccourcis globaux avec référence vers self
        hotkeyManager = GlobalHotkeyManager(connectionManager: connectionManager, menuController: self)
        
        connectionManager.start()
    }
    
    private func setupHotkeyVolumeObserver() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleVolumeChangedViaHotkey),
            name: NSNotification.Name("VolumeChangedViaHotkey"),
            object: nil
        )
    }
    
    @objc private func handleVolumeChangedViaHotkey(_ notification: Notification) {
        guard let volumeStatus = notification.object as? VolumeStatus else { return }
        
        currentVolume = volumeStatus
        volumeController.setCurrentVolume(volumeStatus)
        volumeController.updateSliderFromWebSocket(volumeStatus.volume)
    }
    
    private func updateIcon() {
        DispatchQueue.main.async { [weak self] in
            self?.statusItem.button?.alphaValue = self?.isMiloConnected == true ? 1.0 : 0.5
        }
    }
    
    // NOUVEAU: Méthode publique pour que GlobalHotkeyManager puisse vérifier l'état
    func isMenuCurrentlyOpen() -> Bool {
        return isMenuOpen
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
        isMenuOpen = true  // NOUVEAU: Marquer le menu comme ouvert
        
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
        
        if isMiloConnected {
            Task {
                await refreshState()
                await refreshVolumeStatus()
                
                await MainActor.run {
                    if let menu = self.activeMenu {
                        self.updateMenuInRealTime(menu)
                    }
                }
            }
        }
    }
    
    private func showPreferencesMenu() {
        isMenuOpen = true  // NOUVEAU: Marquer le menu comme ouvert
        
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
        
        if isMiloConnected {
            Task {
                await refreshState()
                await refreshVolumeStatus()
                
                await MainActor.run {
                    if let menu = self.activeMenu {
                        self.updateMenuInRealTime(menu)
                    }
                }
            }
        }
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
        
        let sourceItems = MenuItemFactory.createAudioSourcesSectionWithLoading(
            state: currentState,
            loadingStates: loadingStates,
            loadingTarget: loadingTarget,
            target: self,
            action: #selector(sourceClickedWithLoading)
        )
        sourceItems.forEach { menu.addItem($0) }
        
        // MODIFICATION : Utiliser la nouvelle méthode avec support loading
        let systemItems = MenuItemFactory.createSystemControlsSectionWithLoading(
            state: currentState,
            loadingStates: loadingStates,
            loadingTarget: loadingTarget,
            target: self,
            action: #selector(toggleClickedWithLoading)
        )
        systemItems.forEach { menu.addItem($0) }
    }
    
    private func buildConnectedPreferencesMenu(_ menu: NSMenu) {
        buildConnectedMenuWithLoading(menu)
        
        menu.addItem(NSMenuItem.separator())
        
        let globalHotkeysItem = MenuItemHelper.createSimpleToggleItem(
            title: "Raccourcis volume (⌥↑/↓)",
            isEnabled: hotkeyManager?.isCurrentlyMonitoring() ?? false,
            target: self,
            action: #selector(toggleGlobalHotkeys)
        )
        menu.addItem(globalHotkeysItem)
        
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
        isMenuOpen = false  // NOUVEAU: Marquer le menu comme fermé
        
        // SUPPRIMÉ: forceSendPendingVolume() car plus nécessaire
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
        guard let apiService = connectionManager.getAPIService() else { return }
        guard let sourceId = sender.representedObject as? String else { return }
        
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
                try await apiService.changeSource(sourceId)
            } catch {
                await MainActor.run {
                    self.stopLoadingForSource(sourceId)
                }
            }
        }
    }
    
    @objc private func toggleClickedWithLoading(_ sender: NSMenuItem) {
        guard let apiService = connectionManager.getAPIService() else { return }
        guard let toggleType = sender.representedObject as? String else { return }
        
        // Éviter les actions multiples
        if loadingStates[toggleType] == true { return }
        
        // Éviter de toggler si déjà dans l'état souhaité pendant un autre loading
        let currentlyEnabled: Bool
        switch toggleType {
        case "multiroom":
            currentlyEnabled = currentState?.multiroomEnabled ?? false
        case "equalizer":
            currentlyEnabled = currentState?.equalizerEnabled ?? false
        default:
            return
        }
        
        // Marquer comme en cours de loading
        loadingTarget = toggleType
        loadingStartTimes[toggleType] = Date()
        setLoadingState(for: toggleType, isLoading: true)
        
        // Timer de sécurité (timeout)
        loadingTimers[toggleType]?.invalidate()
        loadingTimers[toggleType] = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: false) { _ in
            Task { @MainActor in
                self.stopLoadingForToggle(toggleType)
            }
        }
        
        Task {
            do {
                switch toggleType {
                case "multiroom":
                    let newState = !currentlyEnabled
                    try await apiService.setMultiroom(newState)
                case "equalizer":
                    let newState = !currentlyEnabled
                    try await apiService.setEqualizer(newState)
                default:
                    break
                }
            } catch {
                await MainActor.run {
                    self.stopLoadingForToggle(toggleType)
                }
            }
        }
    }
    
    @objc private func volumeChanged(_ sender: NSSlider) {
        let newVolume = Int(sender.doubleValue)
        volumeController.handleVolumeChange(newVolume)
    }
    
    @objc private func toggleGlobalHotkeys() {
        guard let hotkeyManager = hotkeyManager else { return }
        
        if hotkeyManager.isCurrentlyMonitoring() {
            hotkeyManager.stopMonitoring()
        } else {
            hotkeyManager.startMonitoring()
            
            // Vérifications multiples pour s'assurer que ça fonctionne
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                hotkeyManager.recheckPermissions()
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                hotkeyManager.recheckPermissions()
            }
            
            // Mettre à jour l'interface après un court délai pour refléter l'état correct
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                if let menu = self?.activeMenu {
                    self?.updateMenuInRealTime(menu)
                }
            }
        }
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
                print("Erreur toggle démarrage: \(error)")
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
    
    // MARK: - Loading State Management (méthode additionnelle pour toggles)
    private func stopLoadingForToggle(_ toggleType: String) {
        setLoadingState(for: toggleType, isLoading: false)
        loadingTimers[toggleType]?.invalidate()
        loadingTimers[toggleType] = nil
        loadingStartTimes[toggleType] = nil
        
        if loadingTarget == toggleType {
            loadingTarget = nil
        }
        
        // NOUVEAU : Forcer la mise à jour de l'interface après la fin du loading d'un toggle
        if let menu = activeMenu {
            updateMenuInRealTime(menu)
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
        isMiloConnected = true
        updateIcon()
        
        if let apiService = connectionManager.getAPIService() {
            volumeController.apiService = apiService
        }
        
        hotkeyManager?.startMonitoring()
        
        Task {
            await refreshState()
            await refreshVolumeStatus()
        }
    }
    
    func miloDidDisconnect() {
        hotkeyManager?.stopMonitoring()
        
        isMiloConnected = false
        updateIcon()
        
        currentState = nil
        currentVolume = nil
        volumeController.apiService = nil
        
        for (sourceId, _) in loadingStates {
            loadingStates[sourceId] = false
            loadingTimers[sourceId]?.invalidate()
            loadingTimers[sourceId] = nil
            loadingStartTimes[sourceId] = nil
        }
        loadingTarget = nil
        
        volumeController.cleanup()
        
        if let menu = activeMenu {
            updateMenuInRealTime(menu)
        }
    }
    
    func didReceiveStateUpdate(_ state: MiloState) {
        currentState = state
        
        // Gérer la fin du loading pour les sources audio
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
        
        // NOUVEAU : Gérer la fin du loading pour les toggles système
        // Les toggles se terminent quand l'état a réellement changé
        for (toggleId, isLoading) in loadingStates {
            if isLoading && ["multiroom", "equalizer"].contains(toggleId) {
                // Toujours arrêter le loading après la durée minimale, peu importe l'état
                // (car l'API a répondu et l'état a été mis à jour)
                let startTime = loadingStartTimes[toggleId] ?? Date()
                let elapsed = Date().timeIntervalSince(startTime)
                let minimumDuration: TimeInterval = 1.0
                
                if elapsed >= minimumDuration {
                    stopLoadingForToggle(toggleId)
                } else {
                    let remainingTime = minimumDuration - elapsed
                    DispatchQueue.main.asyncAfter(deadline: .now() + remainingTime) { [weak self] in
                        self?.stopLoadingForToggle(toggleId)
                    }
                }
            }
        }
        
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
            }
        } catch {
            if (error as NSError).code != NSURLErrorTimedOut {
                // Handle error silently
            }
        }
    }
    
    private func refreshVolumeStatus() async {
        guard let apiService = connectionManager.getAPIService() else { return }
        
        do {
            let volumeStatus = try await apiService.getVolumeStatus()
            await MainActor.run {
                let oldVolume = self.currentVolume?.volume ?? -1
                self.currentVolume = volumeStatus
                self.volumeController.setCurrentVolume(volumeStatus)
                
                if oldVolume != volumeStatus.volume {
                    self.volumeController.updateSliderFromWebSocket(volumeStatus.volume)
                }
            }
        } catch {
            if (error as NSError).code != NSURLErrorTimedOut {
                // Handle error silently
            }
        }
    }
}
