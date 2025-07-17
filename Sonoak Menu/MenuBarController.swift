import SwiftUI
import AppKit

class MenuBarController: NSObject, BonjourServiceDelegate, WebSocketServiceDelegate {
    private var statusItem: NSStatusItem
    private var isOakOSConnected = false
    private var bonjourService: BonjourService!
    private var apiService: OakOSAPIService?
    private var webSocketService: WebSocketService!
    private var currentState: OakOSState?
    private var currentVolume: VolumeStatus?
    
    // Menu qui reste ouvert pour les mises à jour en temps réel
    private var activeMenu: NSMenu?
    
    init(statusItem: NSStatusItem) {
        self.statusItem = statusItem
        super.init()
        
        NSLog("🚀 MenuBarController initialized")
        
        setupStatusItem()
        updateIcon()
        
        bonjourService = BonjourService()
        bonjourService.delegate = self
        
        webSocketService = WebSocketService()
        webSocketService.delegate = self
        
        NSLog("✅ All services initialized")
    }
    
    private func setupStatusItem() {
        statusItem.button?.title = "🎵"
        statusItem.button?.target = self
        statusItem.button?.action = #selector(menuButtonClicked)
    }
    
    private func updateIcon() {
        DispatchQueue.main.async { [weak self] in
            if let button = self?.statusItem.button {
                button.alphaValue = self?.isOakOSConnected == true ? 1.0 : 0.5
            }
        }
    }
    
    @objc private func menuButtonClicked() {
        showMenu()
    }
    
    private func showMenu() {
        let menu = NSMenu()
        menu.font = NSFont.menuFont(ofSize: 13)
        
        if isOakOSConnected {
            createConnectedMenu(menu)
        } else {
            createDisconnectedMenu(menu)
        }
        
        // Garder une référence au menu actif pour les mises à jour en temps réel
        activeMenu = menu
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        
        // Nettoyer la référence quand le menu se ferme
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            if self?.statusItem.menu == nil {
                self?.activeMenu = nil
            }
        }
    }
    
    private func createConnectedMenu(_ menu: NSMenu) {
        guard let state = currentState else {
            createConnectedMenuWithDefaults(menu)
            return
        }
        
        // Sources audio avec icônes SF Symbols natifs
        menu.addItem(createNativeSourceItem("Spotify", iconName: "music.note", isActive: state.activeSource == "librespot", sourceId: "librespot"))
        menu.addItem(createNativeSourceItem("Bluetooth", iconName: "bluetooth", isActive: state.activeSource == "bluetooth", sourceId: "bluetooth"))
        menu.addItem(createNativeSourceItem("macOS", iconName: "desktopcomputer", isActive: state.activeSource == "roc", sourceId: "roc"))
        
        // Séparateur
        menu.addItem(NSMenuItem.separator())
        
        // Volume - Titre
        let volumeHeaderItem = NSMenuItem(title: "Volume", action: nil, keyEquivalent: "")
        volumeHeaderItem.isEnabled = false
        menu.addItem(volumeHeaderItem)
        
        // Slider de volume natif style système
        if let volume = currentVolume {
            let sliderItem = NSMenuItem()
            let sliderView = createNativeSystemVolumeSlider(volume: volume.volume)
            sliderItem.view = sliderView
            menu.addItem(sliderItem)
        }
        
        // Séparateur
        menu.addItem(NSMenuItem.separator())
        
        // Toggles avec icônes SF Symbols natifs
        menu.addItem(createNativeToggleItem("Multiroom", iconName: "speaker.wave.3", isEnabled: state.multiroomEnabled, toggleId: "multiroom"))
        menu.addItem(createNativeToggleItem("Égaliseur", iconName: "slider.horizontal.3", isEnabled: state.equalizerEnabled, toggleId: "equalizer"))
    }
    
    private func createNativeSourceItem(_ title: String, iconName: String, isActive: Bool, sourceId: String) -> NSMenuItem {
        let item = NSMenuItem()
        item.target = self
        item.action = #selector(sourceClicked)
        item.representedObject = sourceId
        
        // Container avec hauteur augmentée pour les marges (6px entre lignes)
        let containerView = ClickableView(frame: NSRect(x: 0, y: 0, width: 200, height: 32))
        containerView.clickHandler = { [weak self] in
            self?.sourceClicked(item)
        }
        
        // Cercle pur sans bordure - 26x26px avec marge de 3px en haut/bas
        let circleView = NSView(frame: NSRect(x: 16, y: 3, width: 26, height: 26))
        circleView.wantsLayer = true
        circleView.layer?.cornerRadius = 13
        
        // Couleur du cercle selon l'état
        if isActive {
            if #available(macOS 10.14, *) {
                circleView.layer?.backgroundColor = NSColor.controlAccentColor.cgColor
            } else {
                circleView.layer?.backgroundColor = NSColor.systemBlue.cgColor
            }
        } else {
            circleView.layer?.backgroundColor = NSColor.quaternaryLabelColor.cgColor
        }
        
        // Icône SF Symbol à l'intérieur du cercle
        let iconImageView = NSImageView(frame: NSRect(x: 5, y: 5, width: 16, height: 16))
        
        if #available(macOS 11.0, *) {
            if let systemImage = NSImage(systemSymbolName: iconName, accessibilityDescription: nil) {
                iconImageView.image = systemImage
            }
        } else {
            iconImageView.image = createFallbackIcon(for: iconName)
        }
        
        // Couleur de l'icône selon l'état
        if isActive {
            iconImageView.contentTintColor = NSColor.white
        } else {
            iconImageView.contentTintColor = NSColor.secondaryLabelColor
        }
        
        circleView.addSubview(iconImageView)
        
        // Texte avec ajustement vertical pour centrage
        let textField = NSTextField(labelWithString: title)
        textField.font = NSFont.menuFont(ofSize: 13)
        textField.textColor = NSColor.labelColor
        textField.frame = NSRect(x: 48, y: 8, width: 140, height: 16)
        textField.isEditable = false
        textField.isBordered = false
        textField.backgroundColor = NSColor.clear
        
        containerView.addSubview(circleView)
        containerView.addSubview(textField)
        
        item.view = containerView
        return item
    }
    
    private func createNativeToggleItem(_ title: String, iconName: String, isEnabled: Bool, toggleId: String) -> NSMenuItem {
        let item = NSMenuItem()
        item.target = self
        item.action = #selector(toggleClicked)
        item.representedObject = toggleId
        
        // Container avec hauteur augmentée pour les marges (6px entre lignes)
        let containerView = ClickableView(frame: NSRect(x: 0, y: 0, width: 200, height: 32))
        containerView.clickHandler = { [weak self] in
            self?.toggleClicked(item)
        }
        
        // Cercle pur sans bordure - 26x26px avec marge de 3px en haut/bas
        let circleView = NSView(frame: NSRect(x: 16, y: 3, width: 26, height: 26))
        circleView.wantsLayer = true
        circleView.layer?.cornerRadius = 13
        
        // Couleur du cercle selon l'état
        if isEnabled {
            if #available(macOS 10.14, *) {
                circleView.layer?.backgroundColor = NSColor.controlAccentColor.cgColor
            } else {
                circleView.layer?.backgroundColor = NSColor.systemBlue.cgColor
            }
        } else {
            circleView.layer?.backgroundColor = NSColor.quaternaryLabelColor.cgColor
        }
        
        // Icône SF Symbol à l'intérieur du cercle
        let iconImageView = NSImageView(frame: NSRect(x: 5, y: 5, width: 16, height: 16))
        
        if #available(macOS 11.0, *) {
            if let systemImage = NSImage(systemSymbolName: iconName, accessibilityDescription: nil) {
                iconImageView.image = systemImage
            }
        } else {
            iconImageView.image = createFallbackIcon(for: iconName)
        }
        
        // Couleur de l'icône selon l'état
        if isEnabled {
            iconImageView.contentTintColor = NSColor.white
        } else {
            iconImageView.contentTintColor = NSColor.secondaryLabelColor
        }
        
        circleView.addSubview(iconImageView)
        
        // Texte avec ajustement vertical pour centrage
        let textField = NSTextField(labelWithString: title)
        textField.font = NSFont.menuFont(ofSize: 13)
        textField.textColor = NSColor.labelColor
        textField.frame = NSRect(x: 48, y: 8, width: 140, height: 16)
        textField.isEditable = false
        textField.isBordered = false
        textField.backgroundColor = NSColor.clear
        
        containerView.addSubview(circleView)
        containerView.addSubview(textField)
        
        item.view = containerView
        return item
    }
    
    private func createNativeSystemVolumeSlider(volume: Int) -> NSView {
        let containerView = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 32))
        
        // Slider avec marge pour cohérence
        let slider = NSSlider(frame: NSRect(x: 20, y: 11, width: 160, height: 10))
        slider.minValue = 0
        slider.maxValue = 100
        slider.doubleValue = Double(volume)
        slider.target = self
        slider.action = #selector(volumeChanged)
        
        // Configuration style système
        slider.sliderType = .linear
        slider.controlSize = .regular
        
        // Style natif blanc comme le volume système
        if #available(macOS 10.14, *) {
            slider.trackFillColor = NSColor.controlAccentColor
        }
        
        slider.wantsLayer = true
        
        containerView.addSubview(slider)
        return containerView
    }
    
    private func createFallbackIcon(for iconName: String) -> NSImage {
        let image = NSImage(size: NSSize(width: 16, height: 16))
        image.lockFocus()
        
        NSColor.labelColor.set()
        
        switch iconName {
        case "music.note":
            // Note de musique simple
            let path = NSBezierPath(ovalIn: NSRect(x: 6, y: 2, width: 4, height: 4))
            path.fill()
            let line = NSBezierPath()
            line.move(to: NSPoint(x: 10, y: 6))
            line.line(to: NSPoint(x: 10, y: 12))
            line.lineWidth = 1.5
            line.stroke()
            
        case "bluetooth":
            // B stylisé
            let path = NSBezierPath()
            path.move(to: NSPoint(x: 6, y: 2))
            path.line(to: NSPoint(x: 6, y: 14))
            path.line(to: NSPoint(x: 10, y: 10))
            path.line(to: NSPoint(x: 8, y: 8))
            path.line(to: NSPoint(x: 10, y: 6))
            path.line(to: NSPoint(x: 6, y: 2))
            path.lineWidth = 1.5
            path.stroke()
            
        case "desktopcomputer":
            // Écran d'ordinateur
            let screen = NSBezierPath(rect: NSRect(x: 3, y: 6, width: 10, height: 7))
            screen.fill()
            let base = NSBezierPath(rect: NSRect(x: 6, y: 4, width: 4, height: 2))
            base.fill()
            
        case "speaker.wave.3":
            // Haut-parleur avec ondes
            let speaker = NSBezierPath(rect: NSRect(x: 2, y: 6, width: 3, height: 4))
            speaker.fill()
            for i in 0..<3 {
                let wave = NSBezierPath()
                wave.move(to: NSPoint(x: 6 + i * 2, y: 6))
                wave.curve(to: NSPoint(x: 6 + i * 2, y: 10),
                          controlPoint1: NSPoint(x: 8 + i * 2, y: 6),
                          controlPoint2: NSPoint(x: 8 + i * 2, y: 10))
                wave.lineWidth = 1
                wave.stroke()
            }
            
        case "slider.horizontal.3":
            // Égaliseur avec barres
            for i in 0..<3 {
                let bar = NSBezierPath(rect: NSRect(x: 4 + i * 3, y: 4 + i * 2, width: 2, height: 8 - i * 2))
                bar.fill()
            }
            
        default:
            // Cercle par défaut
            let path = NSBezierPath(ovalIn: NSRect(x: 4, y: 4, width: 8, height: 8))
            path.fill()
        }
        
        image.unlockFocus()
        return image
    }
    
    private func createConnectedMenuWithDefaults(_ menu: NSMenu) {
        menu.addItem(createNativeSourceItem("Spotify", iconName: "music.note", isActive: true, sourceId: "librespot"))
        menu.addItem(createNativeSourceItem("Bluetooth", iconName: "bluetooth", isActive: false, sourceId: "bluetooth"))
        menu.addItem(createNativeSourceItem("macOS", iconName: "desktopcomputer", isActive: false, sourceId: "roc"))
        
        menu.addItem(NSMenuItem.separator())
        
        let volumeItem = NSMenuItem(title: "Volume", action: nil, keyEquivalent: "")
        volumeItem.isEnabled = false
        menu.addItem(volumeItem)
        
        menu.addItem(NSMenuItem.separator())
        
        menu.addItem(createNativeToggleItem("Multiroom", iconName: "speaker.wave.3", isEnabled: false, toggleId: "multiroom"))
        menu.addItem(createNativeToggleItem("Égaliseur", iconName: "slider.horizontal.3", isEnabled: false, toggleId: "equalizer"))
    }
    
    private func createDisconnectedMenu(_ menu: NSMenu) {
        let item = NSMenuItem(title: "Sonoak n'est pas allumé", action: nil, keyEquivalent: "")
        item.isEnabled = false
        menu.addItem(item)
    }
    
    @objc private func sourceClicked(_ sender: NSMenuItem) {
        guard let apiService = apiService,
              let sourceId = sender.representedObject as? String else { return }
        
        print("Source clicked: \(sourceId)")
        
        Task {
            do {
                try await apiService.changeSource(sourceId)
                // Pas besoin de refreshState() car les WebSockets vont nous notifier
            } catch {
                print("❌ Erreur changement source: \(error)")
            }
        }
    }
    
    @objc private func toggleClicked(_ sender: NSMenuItem) {
        guard let apiService = apiService,
              let toggleType = sender.representedObject as? String else { return }
        
        print("Toggle clicked: \(toggleType)")
        
        Task {
            do {
                if toggleType == "multiroom" {
                    let newState = !(currentState?.multiroomEnabled ?? false)
                    try await apiService.setMultiroom(newState)
                } else if toggleType == "equalizer" {
                    let newState = !(currentState?.equalizerEnabled ?? false)
                    try await apiService.setEqualizer(newState)
                }
                // Pas besoin de refreshState() car les WebSockets vont nous notifier
            } catch {
                print("❌ Erreur toggle: \(error)")
            }
        }
    }
    
    @objc private func volumeChanged(_ sender: NSSlider) {
        let newVolume = Int(sender.doubleValue)
        
        Task {
            do {
                try await apiService?.setVolume(newVolume)
                await refreshVolumeStatus()
            } catch {
                print("❌ Erreur changement volume: \(error)")
            }
        }
    }
    
    private func refreshState() async {
        guard let apiService = apiService else { return }
        
        do {
            let state = try await apiService.fetchState()
            await MainActor.run {
                self.currentState = state
                print("🔄 État mis à jour: source=\(state.activeSource), multiroom=\(state.multiroomEnabled), eq=\(state.equalizerEnabled)")
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
                print("🔊 Volume mis à jour: \(volumeStatus.volume)% (mode: \(volumeStatus.mode))")
            }
        } catch {
            print("❌ Erreur refresh volume: \(error)")
        }
    }
    
    // MARK: - BonjourServiceDelegate
    func oakOSFound(name: String, host: String, port: Int) {
        print("🎵 oakOS détecté: \(name) à \(host):\(port)")
        
        // Éviter les connexions multiples
        if isOakOSConnected {
            print("⚠️ oakOS déjà connecté, ignoré")
            return
        }
        
        // Attendre que le service soit vraiment prêt avant de se connecter
        waitForServiceReady(name: name, host: host, port: port)
    }
    
    private func waitForServiceReady(name: String, host: String, port: Int, attempt: Int = 1) {
        let maxAttempts = 10
        
        let apiService = OakOSAPIService(host: host, port: port)
        
        Task {
            do {
                // Test simple de connectivité
                _ = try await apiService.fetchState()
                
                // Le service répond, on peut se connecter
                await MainActor.run {
                    self.connectToOakOS(name: name, host: host, port: port)
                }
                
            } catch {
                // Le service n'est pas encore prêt
                if attempt < maxAttempts {
                    await MainActor.run {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                            self.waitForServiceReady(name: name, host: host, port: port, attempt: attempt + 1)
                        }
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
        
        // Connecter le WebSocket
        webSocketService.connect(to: host, port: port)
        
        Task {
            await refreshState()
            await refreshVolumeStatus()
        }
    }
    
    func oakOSLost() {
        print("❌ oakOS perdu")
        
        // Éviter les déconnexions multiples
        if !isOakOSConnected {
            print("⚠️ oakOS déjà déconnecté, ignoré")
            return
        }
        
        isOakOSConnected = false
        updateIcon()
        apiService = nil
        currentState = nil
        currentVolume = nil
        
        // Déconnecter le WebSocket
        webSocketService.disconnect()
        
        // Mettre à jour le menu s'il est ouvert
        if let menu = activeMenu {
            updateMenuInRealTime(menu)
        }
    }
}

// MARK: - WebSocketServiceDelegate
extension MenuBarController {
    func didReceiveStateUpdate(_ state: OakOSState) {
        print("🔄 WebSocket state update: \(state.activeSource)")
        currentState = state
        
        // Mettre à jour le menu en temps réel s'il est ouvert
        if let menu = activeMenu {
            updateMenuInRealTime(menu)
        }
    }
    
    func didReceiveVolumeUpdate(_ volume: VolumeStatus) {
        print("🔊 WebSocket volume update: \(volume.volume)%")
        currentVolume = volume
        
        // Mettre à jour le menu en temps réel s'il est ouvert
        if let menu = activeMenu {
            updateMenuInRealTime(menu)
        }
    }
    
    func webSocketDidConnect() {
        print("✅ WebSocket connected")
    }
    
    func webSocketDidDisconnect() {
        print("❌ WebSocket disconnected")
    }
    
    private func updateMenuInRealTime(_ menu: NSMenu) {
        // Recréer le menu avec les nouvelles données
        menu.removeAllItems()
        
        if isOakOSConnected {
            createConnectedMenu(menu)
        } else {
            createDisconnectedMenu(menu)
        }
    }
}

// MARK: - ClickableView Helper Class
class ClickableView: NSView {
    var clickHandler: (() -> Void)?
    
    override func mouseDown(with event: NSEvent) {
        clickHandler?()
    }
    
    override func hitTest(_ point: NSPoint) -> NSView? {
        // Permet à cette vue de recevoir les clics
        return bounds.contains(point) ? self : nil
    }
}
