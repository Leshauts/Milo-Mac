import SwiftUI
import AppKit

// MARK: - Simplified MenuBarController
class MenuBarController: NSObject, BonjourServiceDelegate, WebSocketServiceDelegate {
    private var statusItem: NSStatusItem
    private var isOakOSConnected = false
    private var bonjourService: BonjourService!
    private var apiService: OakOSAPIService?
    private var webSocketService: WebSocketService!
    private var currentState: OakOSState?
    private var currentVolume: VolumeStatus?
    private var activeMenu: NSMenu?
    
    private let volumeController = VolumeController()
    
    // MARK: - Nouvelles propriétés pour le loading
    private var loadingStates: [String: Bool] = [:]
    private var loadingTimers: [String: Timer] = [:]
    private var loadingStartTimes: [String: Date] = [:]  // Pour gérer le délai minimum
    private var loadingTarget: String?  // Quelle source est la cible du loading
    
    init(statusItem: NSStatusItem) {
        self.statusItem = statusItem
        super.init()
        
        setupStatusItem()
        updateIcon()
        setupServices()
    }
    
    private func setupStatusItem() {
        // Utiliser l'icône SVG personnalisée au lieu du texte
        statusItem.button?.image = createCustomIcon()
        statusItem.button?.target = self
        statusItem.button?.action = #selector(menuButtonClicked)
        
        // Configurer l'image pour qu'elle soit template (s'adapte au thème)
        statusItem.button?.image?.isTemplate = true
    }
    
    private func createCustomIcon() -> NSImage {
        // Taille standard pour les icônes de menu bar macOS
        let size = NSSize(width: 22, height: 22)
        let image = NSImage(size: size)
        
        image.lockFocus()
        
        // Convertir les coordonnées SVG (24x24) vers notre taille (22x22)
        let scale = size.width / 24.0
        let context = NSGraphicsContext.current?.cgContext
        context?.scaleBy(x: scale, y: scale)
        
        // Dessiner le path principal (opacité 1.0)
        let path1 = NSBezierPath()
        path1.move(to: NSPoint(x: 12.1329, y: 8.1009)) // Inverser Y pour macOS
        path1.curve(to: NSPoint(x: 18.2837, y: 10.1567),
                   controlPoint1: NSPoint(x: 13.1013, y: 9.7746),
                   controlPoint2: NSPoint(x: 15.4069, y: 10.4476))
        path1.line(to: NSPoint(x: 21.2536, y: 5.0007))
        path1.line(to: NSPoint(x: 11.8209, y: 5.0007))
        path1.curve(to: NSPoint(x: 12.1329, y: 8.1009),
                   controlPoint1: NSPoint(x: 11.5386, y: 6.1542),
                   controlPoint2: NSPoint(x: 11.6232, y: 7.2198))
        path1.close()
        
        // Utiliser blanc pur (#FFF) avec opacité 1.0
        NSColor.white.setFill()
        path1.fill()
        
        // Dessiner le path 2 (opacité 0.7)
        let path2 = NSBezierPath()
        path2.move(to: NSPoint(x: 9.14838, y: 10.9704))
        path2.curve(to: NSPoint(x: 9.03931, y: 5.0013),
                   controlPoint1: NSPoint(x: 10.1293, y: 9.2748),
                   controlPoint2: NSPoint(x: 10.0176, y: 7.1431))
        path2.line(to: NSPoint(x: 2.7464, y: 5.0))
        path2.line(to: NSPoint(x: 7.29157, y: 12.8265))
        path2.curve(to: NSPoint(x: 9.14838, y: 10.9704),
                   controlPoint1: NSPoint(x: 8.0696, y: 12.3585),
                   controlPoint2: NSPoint(x: 8.70418, y: 11.7398))
        path2.close()
        
        NSColor.white.withAlphaComponent(0.7).setFill()
        path2.fill()
        
        // Dessiner le path 3 (opacité 0.34)
        let path3 = NSBezierPath()
        path3.move(to: NSPoint(x: 13.8436, y: 11.7358))
        path3.curve(to: NSPoint(x: 16.8089, y: 12.7154),
                   controlPoint1: NSPoint(x: 14.9045, y: 11.7358),
                   controlPoint2: NSPoint(x: 15.9106, y: 12.0875))
        path3.line(to: NSPoint(x: 12.0397, y: 21.0))
        path3.line(to: NSPoint(x: 8.65524, y: 15.17509))
        path3.curve(to: NSPoint(x: 13.8436, y: 11.7358),
                   controlPoint1: NSPoint(x: 9.92639, y: 13.0651),
                   controlPoint2: NSPoint(x: 11.7799, y: 11.7365))
        path3.close()
        
        NSColor.white.withAlphaComponent(0.34).setFill()
        path3.fill()
        
        image.unlockFocus()
        return image
    }
    
    private func setupServices() {
        bonjourService = BonjourService()
        bonjourService.delegate = self
        
        webSocketService = WebSocketService()
        webSocketService.delegate = self
        
        volumeController.activeMenu = activeMenu
    }
    
    private func updateIcon() {
        DispatchQueue.main.async { [weak self] in
            // Changer l'opacité selon l'état de connexion
            self?.statusItem.button?.alphaValue = self?.isOakOSConnected == true ? 1.0 : 0.5
        }
    }
    
    @objc private func menuButtonClicked() {
        showMenu()
    }
    
    private func showMenu() {
        let menu = NSMenu()
        menu.font = NSFont.menuFont(ofSize: 13)
        
        if isOakOSConnected {
            buildConnectedMenuWithLoading(menu)
        } else {
            buildDisconnectedMenu(menu)
        }
        
        activeMenu = menu
        volumeController.activeMenu = menu
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        
        // Vérifier la fermeture du menu
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            if self?.statusItem.menu == nil {
                self?.handleMenuClosed()
            }
        }
    }
    
    private func buildConnectedMenuWithLoading(_ menu: NSMenu) {
        // 1. Section Volume (en premier)
        let volumeItems = MenuItemFactory.createVolumeSection(
            volume: currentVolume?.volume ?? 50,
            target: self,
            action: #selector(volumeChanged)
        )
        volumeItems.forEach { menu.addItem($0) }
        
        // Configurer le contrôleur de volume
        if let sliderItem = volumeItems.first(where: { $0.view is MenuInteractionView }),
           let sliderView = sliderItem.view as? MenuInteractionView,
           let slider = sliderView.subviews.first(where: { $0 is NSSlider }) as? NSSlider {
            volumeController.setVolumeSlider(slider)
        }
        
        // 2. Sources audio avec support loading
        let sourceItems = MenuItemFactory.createAudioSourcesSectionWithLoading(
            state: currentState,
            loadingStates: loadingStates,
            loadingTarget: loadingTarget,
            target: self,
            action: #selector(sourceClickedWithLoading)
        )
        sourceItems.forEach { menu.addItem($0) }
        
        // 3. Contrôles système (inchangé)
        let systemItems = MenuItemFactory.createSystemControlsSection(
            state: currentState,
            target: self,
            action: #selector(toggleClicked)
        )
        systemItems.forEach { menu.addItem($0) }
    }
    
    private func buildDisconnectedMenu(_ menu: NSMenu) {
        let disconnectedItem = MenuItemFactory.createDisconnectedItem()
        menu.addItem(disconnectedItem)
    }
    
    private func handleMenuClosed() {
        volumeController.forceSendPendingVolume()
        volumeController.cleanup()
        activeMenu = nil
        volumeController.activeMenu = nil
    }
    
    // MARK: - Méthodes de gestion du loading
    private func setLoadingState(for sourceId: String, isLoading: Bool) {
        print("🔄 setLoadingState: \(sourceId) -> \(isLoading)")
        
        // Éviter les mises à jour inutiles
        if loadingStates[sourceId] == isLoading {
            print("⚠️ État déjà à \(isLoading) pour \(sourceId), pas de mise à jour")
            return
        }
        
        let oldState = loadingStates[sourceId] ?? false
        loadingStates[sourceId] = isLoading
        
        // Mettre à jour SEULEMENT l'item spécifique, et seulement si l'état change vraiment
        if let menu = activeMenu, oldState != isLoading {
            print("🎯 Mise à jour spécifique de l'item \(sourceId) (\(oldState) -> \(isLoading))")
            updateSourceLoadingInMenu(menu, sourceId: sourceId, isLoading: isLoading)
        } else if oldState == isLoading {
            print("🔒 Pas de mise à jour UI pour \(sourceId), état identique (\(isLoading))")
        }
    }
    
    private func stopLoadingForSource(_ sourceId: String) {
        setLoadingState(for: sourceId, isLoading: false)
        loadingTimers[sourceId]?.invalidate()
        loadingTimers[sourceId] = nil
        loadingStartTimes[sourceId] = nil
        
        // Reset la cible du loading si c'est cette source
        if loadingTarget == sourceId {
            loadingTarget = nil
        }
    }
    
    private func updateSourceLoadingInMenu(_ menu: NSMenu, sourceId: String, isLoading: Bool) {
        // Trouver l'item correspondant au sourceId
        for item in menu.items {
            if let representedObject = item.representedObject as? String,
               representedObject == sourceId {
                
                // Créer la config pour cet item
                let config = getMenuItemConfig(for: sourceId)
                let loadingIsActive = loadingTarget == sourceId
                
                // Mettre à jour l'état de loading
                CircularMenuItem.updateItemLoadingState(item, isLoading: isLoading, config: config, loadingIsActive: loadingIsActive)
                break
            }
        }
    }
    
    private func getMenuItemConfig(for sourceId: String) -> MenuItemConfig {
        let activeSource = currentState?.activeSource ?? "none"
        let isCurrentlyLoading = loadingStates[sourceId] ?? false
        let isLoadingTarget = loadingTarget == sourceId
        
        // Une source est considérée active si :
        // - Elle est la source active actuelle
        // - ET (pas de loading en cours OU elle est la cible du loading)
        // - ET pas un autre plugin en cours de loading
        let hasOtherLoading = loadingTarget != nil && loadingTarget != sourceId
        let isActive = (activeSource == sourceId) && !hasOtherLoading && (!isCurrentlyLoading || isLoadingTarget)
        
        switch sourceId {
        case "librespot":
            return MenuItemConfig(
                title: "Spotify",
                iconName: "music.note",
                isActive: isActive,
                target: self,
                action: #selector(sourceClickedWithLoading),
                representedObject: "librespot"
            )
        case "bluetooth":
            return MenuItemConfig(
                title: "Bluetooth",
                iconName: "bluetooth",
                isActive: isActive,
                target: self,
                action: #selector(sourceClickedWithLoading),
                representedObject: "bluetooth"
            )
        case "roc":
            return MenuItemConfig(
                title: "macOS",
                iconName: "desktopcomputer",
                isActive: isActive,
                target: self,
                action: #selector(sourceClickedWithLoading),
                representedObject: "roc"
            )
        default:
            return MenuItemConfig(
                title: "Unknown",
                iconName: "music.note",
                isActive: false,
                target: self,
                action: #selector(sourceClickedWithLoading),
                representedObject: sourceId
            )
        }
    }
    
    // MARK: - Actions
    @objc private func sourceClickedWithLoading(_ sender: NSMenuItem) {
        guard let apiService = apiService,
              let sourceId = sender.representedObject as? String else { return }
        
        // Empêcher les clics multiples si déjà en loading
        if loadingStates[sourceId] == true {
            print("⚠️ Source \(sourceId) déjà en loading, ignorer le clic")
            return
        }
        
        print("🔄 Démarrage du loading pour \(sourceId)")
        
        // Définir la cible du loading pour l'affichage
        loadingTarget = sourceId
        
        // Enregistrer l'heure de début
        loadingStartTimes[sourceId] = Date()
        
        // Démarrer le loading
        setLoadingState(for: sourceId, isLoading: true)
        
        // Timer de sécurité pour arrêter le loading après 15 secondes max (augmenté pour voir)
        loadingTimers[sourceId]?.invalidate()
        loadingTimers[sourceId] = Timer.scheduledTimer(withTimeInterval: 15.0, repeats: false) { _ in
            Task { @MainActor in
                print("⏱️ Timeout loading pour \(sourceId)")
                self.stopLoadingForSource(sourceId)
            }
        }
        
        Task {
            do {
                try await apiService.changeSource(sourceId)
                print("✅ API call réussie pour \(sourceId)")
            } catch {
                print("❌ Erreur changement source: \(error)")
                // Arrêter le loading en cas d'erreur
                await MainActor.run {
                    print("❌ Arrêt du loading suite à l'erreur pour \(sourceId)")
                    self.stopLoadingForSource(sourceId)
                }
            }
        }
    }
    
    @objc private func toggleClicked(_ sender: NSMenuItem) {
        guard let apiService = apiService,
              let toggleType = sender.representedObject as? String else { return }
        
        Task {
            do {
                switch toggleType {
                case "multiroom":
                    let newState = !(currentState?.multiroomEnabled ?? false)
                    try await apiService.setMultiroom(newState)
                case "equalizer":
                    let newState = !(currentState?.equalizerEnabled ?? false)
                    try await apiService.setEqualizer(newState)
                default:
                    break
                }
            } catch {
                print("❌ Erreur toggle: \(error)")
            }
        }
    }
    
    @objc private func volumeChanged(_ sender: NSSlider) {
        let newVolume = Int(sender.doubleValue)
        volumeController.handleVolumeChange(newVolume)
    }
    
    // MARK: - State Management
    private func refreshState() async {
        guard let apiService = apiService else { return }
        
        do {
            let state = try await apiService.fetchState()
            await MainActor.run {
                self.currentState = state
            }
        } catch {
            print("❌ Erreur refresh état: \(error)")
        }
    }
    
    private func refreshVolumeStatus() async {
        guard let apiService = apiService else { return }
        
        do {
            let volumeStatus = try await apiService.getVolumeStatus()
            await MainActor.run {
                self.currentVolume = volumeStatus
                self.volumeController.setCurrentVolume(volumeStatus)
            }
        } catch {
            print("❌ Erreur refresh volume: \(error)")
        }
    }
    
    // MARK: - BonjourServiceDelegate
    func oakOSFound(name: String, host: String, port: Int) {
        if isOakOSConnected { return }
        waitForServiceReady(name: name, host: host, port: port)
    }
    
    private func waitForServiceReady(name: String, host: String, port: Int, attempt: Int = 1) {
        let maxAttempts = 10
        let apiService = OakOSAPIService(host: host, port: port)
        
        Task { @MainActor in
            do {
                _ = try await apiService.fetchState()
                self.connectToOakOS(name: name, host: host, port: port)
            } catch {
                if attempt < maxAttempts {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                        self?.waitForServiceReady(name: name, host: host, port: port, attempt: attempt + 1)
                    }
                } else {
                    NSLog("❌ Service non accessible après \(maxAttempts) tentatives")
                }
            }
        }
    }
    
    private func connectToOakOS(name: String, host: String, port: Int) {
        isOakOSConnected = true
        updateIcon()
        
        apiService = OakOSAPIService(host: host, port: port)
        volumeController.apiService = apiService
        
        webSocketService.connect(to: host, port: port)
        
        Task {
            await refreshState()
            await refreshVolumeStatus()
        }
    }
    
    func oakOSLost() {
        if !isOakOSConnected { return }
        
        isOakOSConnected = false
        updateIcon()
        apiService = nil
        volumeController.apiService = nil
        currentState = nil
        currentVolume = nil
        
        // Nettoyer les états de loading
        for (sourceId, _) in loadingStates {
            loadingStates[sourceId] = false
            loadingTimers[sourceId]?.invalidate()
            loadingTimers[sourceId] = nil
            loadingStartTimes[sourceId] = nil
        }
        loadingTarget = nil
        
        volumeController.cleanup()
        webSocketService.disconnect()
        
        if let menu = activeMenu {
            updateMenuInRealTime(menu)
        }
    }
    
    // MARK: - WebSocketServiceDelegate
    func didReceiveStateUpdate(_ state: OakOSState) {
        print("📡 État reçu: activeSource=\(state.activeSource), transitioning=\(state.isTransitioning)")
        currentState = state
        
        // Ne stopper le loading que si la transition est terminée ET la source a changé
        if !state.isTransitioning {
            for (sourceId, isLoading) in loadingStates {
                if isLoading {
                    print("🔍 Checking loading state for \(sourceId), current active: \(state.activeSource)")
                    // Vérifier si cette source est maintenant active (transition réussie)
                    if state.activeSource == sourceId {
                        // Transition réussie, mais respecter le délai minimum
                        let startTime = loadingStartTimes[sourceId] ?? Date()
                        let elapsed = Date().timeIntervalSince(startTime)
                        let minimumDuration: TimeInterval = 1.0  // 1 seconde minimum
                        
                        if elapsed >= minimumDuration {
                            // Délai minimum écoulé, arrêter immédiatement
                            print("✅ Transition réussie vers \(sourceId), arrêt du loading (délai écoulé)")
                            stopLoadingForSource(sourceId)
                        } else {
                            // Attendre le délai minimum
                            let remainingTime = minimumDuration - elapsed
                            print("⏱️ Attendre \(remainingTime)s avant d'arrêter le loading pour \(sourceId)")
                            
                            DispatchQueue.main.asyncAfter(deadline: .now() + remainingTime) { [weak self] in
                                print("✅ Délai minimum écoulé, arrêt du loading pour \(sourceId)")
                                self?.stopLoadingForSource(sourceId)
                            }
                        }
                    }
                    // Sinon, laisser le loading continuer (cas d'échec, géré par le timer de sécurité)
                }
            }
        } else {
            print("⏳ Transition en cours, loading continue...")
        }
        
        // NE PAS recréer le menu pendant un loading !
        let hasActiveLoading = loadingStates.values.contains(true)
        if let menu = activeMenu, !hasActiveLoading {
            print("🔄 Mise à jour du menu (pas de loading actif)")
            updateMenuInRealTime(menu)
        } else if hasActiveLoading {
            print("⏸️ Loading en cours, menu non recréé pour préserver l'animation")
        }
    }
    
    func didReceiveVolumeUpdate(_ volume: VolumeStatus) {
        currentVolume = volume
        volumeController.setCurrentVolume(volume)
        volumeController.updateSliderFromWebSocket(volume.volume)
    }
    
    func webSocketDidConnect() {
        // Connexion établie
    }
    
    func webSocketDidDisconnect() {
        // Connexion perdue
    }
    
    private func updateMenuInRealTime(_ menu: NSMenu) {
        menu.removeAllItems()
        
        if isOakOSConnected {
            buildConnectedMenuWithLoading(menu)
        } else {
            buildDisconnectedMenu(menu)
        }
    }
}
