import SwiftUI
import AppKit
import ServiceManagement

// MARK: - MenuBarController
class MenuBarController: NSObject, BonjourServiceDelegate, WebSocketServiceDelegate {
    private var statusItem: NSStatusItem
    private var isMiloConnected = false
    private var bonjourService: BonjourService!
    private var apiService: MiloAPIService?
    private var webSocketService: WebSocketService!
    private var currentState: MiloState?
    private var currentVolume: VolumeStatus?
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
        updateIcon()
        setupServices()
    }
    
    private func setupStatusItem() {
        statusItem.button?.image = createCustomIcon()
        statusItem.button?.target = self
        statusItem.button?.action = #selector(menuButtonClicked)
        statusItem.button?.image?.isTemplate = true
    }
    
    private func createCustomIcon() -> NSImage {
        let size = NSSize(width: 22, height: 22)
        let image = NSImage(size: size)
        
        image.lockFocus()
        
        let scale = size.width / 24.0
        let context = NSGraphicsContext.current?.cgContext
        context?.scaleBy(x: scale, y: scale)
        
        // Path principal
        let path1 = NSBezierPath()
        path1.move(to: NSPoint(x: 12.1329, y: 8.1009))
        path1.curve(to: NSPoint(x: 18.2837, y: 10.1567),
                   controlPoint1: NSPoint(x: 13.1013, y: 9.7746),
                   controlPoint2: NSPoint(x: 15.4069, y: 10.4476))
        path1.line(to: NSPoint(x: 21.2536, y: 5.0007))
        path1.line(to: NSPoint(x: 11.8209, y: 5.0007))
        path1.curve(to: NSPoint(x: 12.1329, y: 8.1009),
                   controlPoint1: NSPoint(x: 11.5386, y: 6.1542),
                   controlPoint2: NSPoint(x: 11.6232, y: 7.2198))
        path1.close()
        
        NSColor.white.setFill()
        path1.fill()
        
        // Path 2
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
        
        // Path 3
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
        
        // Méthode moderne sans popUpMenu
        displayMenu(menu)
    }
    
    private func showPreferencesMenu() {
        let menu = NSMenu()
        menu.font = NSFont.menuFont(ofSize: 13)
        
        if isMiloConnected {
            buildConnectedPreferencesMenu(menu)
        } else {
            buildDisconnectedPreferencesMenu(menu)  // CORRECTION : Menu préférences même déconnecté
        }
        
        activeMenu = menu
        isPreferencesMenuActive = true
        
        // Méthode moderne sans popUpMenu
        displayMenu(menu)
    }
    
    private func displayMenu(_ menu: NSMenu) {
        // AJOUT : Activer l'app pour que les contrôles gardent leur couleur
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
    
    private func buildConnectedPreferencesMenu(_ menu: NSMenu) {
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
        let launchAtLoginItem = createSimpleToggleItem(
            title: "Démarrer au démarrage du Mac",
            isEnabled: isLaunchAtLoginEnabled(),
            target: self,
            action: #selector(toggleLaunchAtLogin)
        )
        menu.addItem(launchAtLoginItem)
        
        // Quitter
        let quitItem = createSimpleMenuItem(
            title: "Quitter",
            target: self,
            action: #selector(quitApplication)
        )
        menu.addItem(quitItem)
    }
    
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
    
    private func buildDisconnectedMenu(_ menu: NSMenu) {
        let disconnectedItem = MenuItemFactory.createDisconnectedItem()
        menu.addItem(disconnectedItem)
    }
    
    // AJOUT : Menu préférences quand Milo est déconnecté
    private func buildDisconnectedPreferencesMenu(_ menu: NSMenu) {
        // Message de déconnexion
        let disconnectedItem = MenuItemFactory.createDisconnectedItem()
        menu.addItem(disconnectedItem)
        
        // Section préférences même déconnecté
        menu.addItem(NSMenuItem.separator())
        
        // Toggle démarrage automatique (toujours accessible)
        let launchAtLoginItem = createSimpleToggleItem(
            title: "Démarrer au démarrage du Mac",
            isEnabled: isLaunchAtLoginEnabled(),
            target: self,
            action: #selector(toggleLaunchAtLogin)
        )
        menu.addItem(launchAtLoginItem)
        
        // Quitter (toujours accessible)
        let quitItem = createSimpleMenuItem(
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
    
    // MARK: - Gestion démarrage automatique
    private func isLaunchAtLoginEnabled() -> Bool {
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        } else {
            let bundleIdentifier = Bundle.main.bundleIdentifier ?? ""
            return SMLoginItemSetEnabled(bundleIdentifier as CFString, false)
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
    
    // MARK: - Items de menu simples
    private func createSimpleMenuItem(title: String, target: AnyObject, action: Selector) -> NSMenuItem {
        let item = NSMenuItem()
        
        let containerView = SimpleHoverableView(frame: NSRect(x: 0, y: 0, width: 300, height: 32))
        
        let textField = NSTextField(labelWithString: title)
        textField.font = NSFont.menuFont(ofSize: 13)
        textField.textColor = NSColor.labelColor
        textField.frame = NSRect(x: 12, y: 8, width: 200, height: 16)
        textField.isEditable = false
        textField.isBordered = false
        textField.backgroundColor = NSColor.clear
        
        containerView.addSubview(textField)
        containerView.clickHandler = { [weak target] in
            _ = target?.perform(action)
        }
        
        item.view = containerView
        return item
    }
    
    private func createSimpleToggleItem(title: String, isEnabled: Bool, target: AnyObject, action: Selector) -> NSMenuItem {
        let item = NSMenuItem()
        
        let containerView = SimpleHoverableView(frame: NSRect(x: 0, y: 0, width: 300, height: 32))
        
        let textField = NSTextField(labelWithString: title)
        textField.font = NSFont.menuFont(ofSize: 13)
        textField.textColor = NSColor.labelColor
        textField.frame = NSRect(x: 12, y: 8, width: 200, height: 16)
        textField.isEditable = false
        textField.isBordered = false
        textField.backgroundColor = NSColor.clear
        
        // Toggle switch petit format (26x16px)
        let toggle = NSSwitch()
        toggle.state = isEnabled ? .on : .off
        toggle.frame = NSRect(x: 262, y: 8, width: 26, height: 16)
        toggle.controlSize = .small
        toggle.target = target
        toggle.action = action
        
        containerView.addSubview(textField)
        containerView.addSubview(toggle)
        
        containerView.clickHandler = {
            toggle.state = toggle.state == .on ? .off : .on
            _ = target.perform(action, with: toggle)
        }
        
        item.view = containerView
        return item
    }
    
    // MARK: - Gestion du loading
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
    
    // MARK: - Actions
    @objc private func sourceClickedWithLoading(_ sender: NSMenuItem) {
        guard let apiService = apiService,
              let sourceId = sender.representedObject as? String else { return }
        
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
    func MiloFound(name: String, host: String, port: Int) {
        if isMiloConnected { return }
        waitForServiceReady(name: name, host: host, port: port)
    }
    
    private func waitForServiceReady(name: String, host: String, port: Int, attempt: Int = 1) {
        let maxAttempts = 10
        let apiService = MiloAPIService(host: host, port: port)
        
        Task { @MainActor in
            do {
                _ = try await apiService.fetchState()
                self.connectToMilo(name: name, host: host, port: port)
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
    
    private func connectToMilo(name: String, host: String, port: Int) {
        isMiloConnected = true
        updateIcon()
        
        apiService = MiloAPIService(host: host, port: port)
        volumeController.apiService = apiService
        
        webSocketService.connect(to: host, port: port)
        
        Task {
            await refreshState()
            await refreshVolumeStatus()
        }
    }
    
    func MiloLost() {
        if !isMiloConnected { return }
        
        isMiloConnected = false
        updateIcon()
        apiService = nil
        volumeController.apiService = nil
        currentState = nil
        currentVolume = nil
        
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
    
    func webSocketDidConnect() {}
    func webSocketDidDisconnect() {}
    
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
                buildDisconnectedPreferencesMenu(menu)  // CORRECTION : Préférences même déconnecté
            } else {
                buildDisconnectedMenu(menu)
            }
        }
    }
}

// MARK: - Simple Hoverable View
class SimpleHoverableView: NSView {
    var clickHandler: (() -> Void)?
    private var trackingArea: NSTrackingArea?
    private var hoverBackgroundLayer: CALayer?
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupView()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }
    
    private func setupView() {
        wantsLayer = true
        setupTrackingArea()
        
        hoverBackgroundLayer = CALayer()
        hoverBackgroundLayer?.frame = NSRect(x: 5, y: 0, width: bounds.width - 10, height: bounds.height)
        hoverBackgroundLayer?.cornerRadius = 6
        hoverBackgroundLayer?.backgroundColor = NSColor.clear.cgColor
        
        layer?.insertSublayer(hoverBackgroundLayer!, at: 0)
    }
    
    private func setupTrackingArea() {
        let options: NSTrackingArea.Options = [
            .mouseEnteredAndExited,
            .activeAlways,
            .inVisibleRect
        ]
        
        trackingArea = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
        addTrackingArea(trackingArea!)
    }
    
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        
        if let trackingArea = trackingArea {
            removeTrackingArea(trackingArea)
        }
        
        setupTrackingArea()
    }
    
    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        
        let hoverColor: NSColor
        if #available(macOS 10.14, *) {
            hoverColor = NSColor.tertiaryLabelColor
        } else {
            hoverColor = NSColor.lightGray.withAlphaComponent(0.2)
        }
        
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        hoverBackgroundLayer?.backgroundColor = hoverColor.cgColor
        CATransaction.commit()
    }
    
    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        hoverBackgroundLayer?.backgroundColor = NSColor.clear.cgColor
        CATransaction.commit()
    }
    
    override func mouseDown(with event: NSEvent) {
        clickHandler?()
    }
    
    override func hitTest(_ point: NSPoint) -> NSView? {
        return bounds.contains(point) ? self : nil
    }
}
