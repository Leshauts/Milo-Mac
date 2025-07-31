import SwiftUI
import AppKit
import ServiceManagement

// MARK: - MenuBarController
class MenuBarController: NSObject, MiloConnectionDelegate, WebSocketServiceDelegate {
    private var statusItem: NSStatusItem
    internal var isMiloConnected = false  // internal pour extensions
    private var connectionService: MiloConnectionService!
    internal var apiService: MiloAPIService?  // internal pour extensions
    private var webSocketService: WebSocketService!
    internal var currentState: MiloState?  // internal pour extensions
    internal var currentVolume: VolumeStatus?  // internal pour extensions
    internal var activeMenu: NSMenu?  // internal pour extensions
    internal var isPreferencesMenuActive = false  // internal pour extensions
    
    internal let volumeController = VolumeController()  // internal pour extensions
    
    // Loading states - internal pour extensions
    internal var loadingStates: [String: Bool] = [:]
    internal var loadingTimers: [String: Timer] = [:]
    internal var loadingStartTimes: [String: Date] = [:]
    internal var loadingTarget: String?
    
    // NOUVEAU : Monitoring périodique de l'état de connexion
    private var connectionSyncTimer: Timer?
    private let connectionSyncInterval: TimeInterval = 5.0
    
    init(statusItem: NSStatusItem) {
        self.statusItem = statusItem
        super.init()
        
        setupStatusItem()
        updateIcon()
        setupServices()
        startConnectionSyncMonitoring()
    }
    
    private func setupStatusItem() {
        statusItem.button?.image = createCustomIcon()
        statusItem.button?.target = self
        statusItem.button?.action = #selector(menuButtonClicked)
        statusItem.button?.image?.isTemplate = true
    }
    
    private func createCustomIcon() -> NSImage? {
        // Essayer de charger l'icône depuis les assets
        if let image = NSImage(named: "menubar-icon") {
            image.isTemplate = true  // Important pour que l'icône s'adapte au thème (dark/light)
            image.size = NSSize(width: 22, height: 22)
            return image
        }
        
        // Fallback vers l'icône système si l'asset n'est pas trouvé
        let fallbackImage = NSImage(systemSymbolName: "speaker.wave.3", accessibilityDescription: "Milo")
        fallbackImage?.isTemplate = true
        return fallbackImage
    }
    
    private func setupServices() {
        connectionService = MiloConnectionService()
        connectionService.delegate = self
        
        webSocketService = WebSocketService()
        webSocketService.delegate = self
        
        volumeController.activeMenu = activeMenu
    }
    
    // NOUVEAU : Surveillance synchronisée des connexions - intervalle raisonnable
    private func startConnectionSyncMonitoring() {
        connectionSyncTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in  // 2 secondes
            self?.syncConnectionStates()
        }
    }
    
    // NOUVEAU : Synchronisation des états de connexion
    private func syncConnectionStates() {
        let tcpConnected = connectionService.getCurrentConnectionState()
        let wsConnected = webSocketService.getConnectionState()
        let shouldBeConnected = tcpConnected && wsConnected
        
        // CORRECTION : Logique plus conservative
        if isMiloConnected && !shouldBeConnected {
            NSLog("🔄 Service failure detected - disconnecting (TCP: \(tcpConnected), WS: \(wsConnected))")
            disconnectFromMilo()
        } else if !isMiloConnected && shouldBeConnected {
            NSLog("🎯 Both services ready - connecting (TCP: \(tcpConnected), WS: \(wsConnected))")
            markAsConnected()
        }
        
        // AMÉLIORATION : Forces de reconnexion beaucoup moins agressives
        if tcpConnected && !wsConnected && !isMiloConnected {
            // Seulement si on n'est pas connecté du tout
            NSLog("🔄 TCP OK but WebSocket down - gentle WS reconnect")
            DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) { [weak self] in
                // Vérifier à nouveau avant de forcer
                if self?.webSocketService.getConnectionState() == false {
                    self?.webSocketService.forceReconnect()
                }
            }
        }
        
        if !tcpConnected && wsConnected {
            NSLog("⚠️ WebSocket OK but TCP down - investigating...")
            // Pas de force reconnect pour TCP, laisser faire naturellement
        }
    }
    
    private func disconnectFromMilo() {
        isMiloConnected = false
        updateIcon()
        
        // Nettoyer les états
        apiService = nil
        volumeController.apiService = nil
        currentState = nil
        currentVolume = nil
        
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
    
    private func markAsConnected() {
        isMiloConnected = true
        updateIcon()
        
        // CORRECTION : Toujours recréer l'apiService pour être sûr qu'il soit fonctionnel
        NSLog("🔧 (Re)creating API service for milo.local")
        apiService = MiloAPIService(host: "milo.local", port: 80)
        volumeController.apiService = apiService
        
        // Rafraîchir l'état
        Task {
            await refreshState()
            await refreshVolumeStatus()
        }
    }
    
    internal func updateIcon() {  // internal pour extensions
        DispatchQueue.main.async { [weak self] in
            self?.statusItem.button?.alphaValue = self?.isMiloConnected == true ? 1.0 : 0.5
        }
    }
    
    @objc private func menuButtonClicked() {
        // Réinitialiser le menu
        statusItem.menu = nil
        
        // Détecter Option + clic
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
        // Activer l'app pour que les contrôles gardent leur couleur
        NSApp.activate(ignoringOtherApps: true)
        
        // Assigner le menu au statusItem
        statusItem.menu = menu
        
        // Simuler le clic pour ouvrir le menu
        if let button = statusItem.button {
            button.performClick(nil)
        }
        
        // Nettoyer la référence après un délai pour éviter la persistance
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.statusItem.menu = nil
            self?.monitorMenuClosure()
        }
    }
    
    // MARK: - Menu Building - internal pour extensions
    internal func buildConnectedPreferencesMenu(_ menu: NSMenu) {
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
    
    internal func buildConnectedMenuWithLoading(_ menu: NSMenu) {
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
    
    internal func buildDisconnectedMenu(_ menu: NSMenu) {
        let disconnectedItem = MenuItemFactory.createDisconnectedItem()
        menu.addItem(disconnectedItem)
    }
    
    internal func buildDisconnectedPreferencesMenu(_ menu: NSMenu) {
        // Message de déconnexion
        let disconnectedItem = MenuItemFactory.createDisconnectedItem()
        menu.addItem(disconnectedItem)
        
        // Section préférences même déconnecté
        menu.addItem(NSMenuItem.separator())
        
        // Toggle démarrage automatique (toujours accessible)
        let launchAtLoginItem = MenuItemHelper.createSimpleToggleItem(
            title: "Démarrer au démarrage du Mac",
            isEnabled: isLaunchAtLoginEnabled(),
            target: self,
            action: #selector(toggleLaunchAtLogin)
        )
        menu.addItem(launchAtLoginItem)
        
        // Quitter (toujours accessible)
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
        guard let apiService = apiService else {
            NSLog("❌ sourceClickedWithLoading: apiService is nil!")
            return
        }
        guard let sourceId = sender.representedObject as? String else {
            NSLog("❌ sourceClickedWithLoading: invalid sourceId")
            return
        }
        
        NSLog("🎯 sourceClickedWithLoading: \(sourceId) with apiService: \(apiService)")
        
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
        guard let apiService = apiService else {
            NSLog("❌ toggleClicked: apiService is nil!")
            return
        }
        guard let toggleType = sender.representedObject as? String else {
            NSLog("❌ toggleClicked: invalid toggleType")
            return
        }
        
        NSLog("🎯 toggleClicked: \(toggleType) with apiService: \(apiService)")
        
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
    
    deinit {
        connectionSyncTimer?.invalidate()
    }
}

// MARK: - Loading State Management
extension MenuBarController {
    func setLoadingState(for sourceId: String, isLoading: Bool) {
        if loadingStates[sourceId] == isLoading { return }
        
        let oldState = loadingStates[sourceId] ?? false
        loadingStates[sourceId] = isLoading
        
        if let menu = activeMenu, oldState != isLoading {
            updateMenuInRealTime(menu)
        }
    }
    
    func stopLoadingForSource(_ sourceId: String) {
        setLoadingState(for: sourceId, isLoading: false)
        loadingTimers[sourceId]?.invalidate()
        loadingTimers[sourceId] = nil
        loadingStartTimes[sourceId] = nil
        
        if loadingTarget == sourceId {
            loadingTarget = nil
        }
    }
    
    func updateMenuInRealTime(_ menu: NSMenu) {
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

// MARK: - State Management
extension MenuBarController {
    func refreshState() async {
        guard let apiService = apiService else { return }
        
        do {
            let state = try await apiService.fetchState()
            await MainActor.run {
                self.currentState = state
                NSLog("📊 State refreshed: \(state.activeSource)")
            }
        } catch {
            NSLog("❌ Erreur refresh état: \(error)")
            
            // Si l'API ne répond plus, considérer comme déconnecté
            await MainActor.run {
                self.connectionService.forceReconnect()
            }
        }
    }
    
    func refreshVolumeStatus() async {
        guard let apiService = apiService else { return }
        
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

// MARK: - MiloConnectionDelegate
extension MenuBarController {
    func miloFound(host: String, port: Int) {
        if isMiloConnected {
            NSLog("ℹ️ Already connected to Milo")
            return
        }
        
        NSLog("✅ Milo found at \(host):\(port)")
        waitForServiceReady(host: host, port: port)
    }
    
    private func waitForServiceReady(host: String, port: Int, attempt: Int = 1) {
        let maxAttempts = 15  // Augmenté pour plus de patience
        let apiService = MiloAPIService(host: host, port: port)
        
        Task { @MainActor in
            do {
                _ = try await apiService.fetchState()
                self.connectToMilo(host: host, port: port)
            } catch {
                NSLog("⏳ Service not ready (attempt \(attempt)/\(maxAttempts)): \(error.localizedDescription)")
                
                if attempt < maxAttempts {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                        self?.waitForServiceReady(host: host, port: port, attempt: attempt + 1)
                    }
                } else {
                    NSLog("❌ Service non accessible après \(maxAttempts) tentatives")
                }
            }
        }
    }
    
    private func connectToMilo(host: String, port: Int) {
        guard !isMiloConnected else { return }
        
        NSLog("🎯 Setting up Milo services...")
        
        // CORRECTION : Ne pas marquer comme connecté tout de suite
        // Laisser le sync monitor détecter quand les deux services sont prêts
        
        apiService = MiloAPIService(host: host, port: port)
        volumeController.apiService = apiService
        
        // Connecter WebSocket seulement si pas déjà en cours
        if !webSocketService.getConnectionState() {
            webSocketService.connect(to: host, port: port)
        }
    }
    
    func miloLost() {
        guard isMiloConnected else { return }
        
        NSLog("💔 Milo connection lost - cleaning up")
        disconnectFromMilo()
    }
}

// MARK: - WebSocketServiceDelegate
extension MenuBarController {
    func webSocketDidConnect() {
        NSLog("🌐 WebSocket connected successfully")
        
        // CORRECTION : Appeler markAsConnected() au lieu de juste mettre isMiloConnected = true
        let tcpConnected = connectionService.getCurrentConnectionState()
        
        if tcpConnected && !isMiloConnected {
            NSLog("🎯 Both services connected - calling markAsConnected()")
            markAsConnected()  // ✅ CORRECTION : Appeler markAsConnected() qui crée l'apiService
        }
        
        // Rafraîchir l'état si on était déjà connecté
        if isMiloConnected {
            Task {
                await refreshState()
                await refreshVolumeStatus()
            }
        }
    }
    
    func webSocketDidDisconnect() {
        NSLog("🌐 WebSocket disconnected")
        
        // CORRECTION : Ne pas marquer comme déconnecté immédiatement
        // Laisser le sync monitor gérer la logique de déconnexion
        // Le WebSocket peut se reconnecter automatiquement
    }
    
    func didReceiveStateUpdate(_ state: MiloState) {
        currentState = state
        
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
}
