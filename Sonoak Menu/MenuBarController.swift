import SwiftUI
import AppKit

// MARK: - Constants
private struct Constants {
    static let volumeDebounceDelay: TimeInterval = 0.03
    static let volumeImmediateSendThreshold: TimeInterval = 0.1
    static let userInteractionTimeout: TimeInterval = 0.3
    static let menuCloseCheckDelay: TimeInterval = 0.1
    static let reconnectDelay: TimeInterval = 2.0
    static let maxReconnectAttempts = 10
    
    static let circleSize: CGFloat = 26
    static let circleMargin: CGFloat = 3
    static let iconSize: CGFloat = 16
    static let containerHeight: CGFloat = 32
    static let containerWidth: CGFloat = 200
}

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

// MARK: - UI Factory
class UIFactory {
    private static var iconCache: [String: NSImage] = [:]
    
    static func createCircularItem(
        title: String,
        iconName: String,
        isActive: Bool,
        target: AnyObject,
        action: Selector,
        representedObject: Any?
    ) -> NSMenuItem {
        let item = NSMenuItem()
        item.target = target
        item.action = action
        item.representedObject = representedObject
        
        let containerView = ClickableView(frame: NSRect(x: 0, y: 0, width: Constants.containerWidth, height: Constants.containerHeight))
        containerView.clickHandler = { [weak target] in
            _ = target?.perform(action, with: item)
        }
        
        // Cercle
        let circleView = NSView(frame: NSRect(x: 16, y: Constants.circleMargin, width: Constants.circleSize, height: Constants.circleSize))
        circleView.wantsLayer = true
        circleView.layer?.cornerRadius = Constants.circleSize / 2
        
        // Couleur du cercle
        if isActive {
            if #available(macOS 10.14, *) {
                circleView.layer?.backgroundColor = NSColor.controlAccentColor.cgColor
            } else {
                circleView.layer?.backgroundColor = NSColor.systemBlue.cgColor
            }
        } else {
            circleView.layer?.backgroundColor = NSColor.quaternaryLabelColor.cgColor
        }
        
        // Icône
        let iconImageView = NSImageView(frame: NSRect(x: 5, y: 5, width: Constants.iconSize, height: Constants.iconSize))
        iconImageView.image = getCachedIcon(iconName)
        iconImageView.contentTintColor = isActive ? NSColor.white : NSColor.secondaryLabelColor
        
        circleView.addSubview(iconImageView)
        
        // Texte
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
    
    static func createVolumeSlider(volume: Int, target: AnyObject, action: Selector) -> NSView {
        let containerView = MenuInteractionView(frame: NSRect(x: 0, y: 0, width: Constants.containerWidth, height: Constants.containerHeight))
        
        let slider = NSSlider(frame: NSRect(x: 20, y: 11, width: 160, height: 10))
        slider.minValue = 0
        slider.maxValue = 100
        slider.doubleValue = Double(volume)
        slider.target = target
        slider.action = action
        slider.sliderType = .linear
        slider.controlSize = .regular
        slider.isContinuous = true
        
        if #available(macOS 10.14, *) {
            slider.trackFillColor = NSColor.controlAccentColor
        }
        
        containerView.addSubview(slider)
        return containerView
    }
    
    private static func getCachedIcon(_ iconName: String) -> NSImage {
        if let cached = iconCache[iconName] {
            return cached
        }
        
        let icon: NSImage
        if #available(macOS 11.0, *) {
            icon = NSImage(systemSymbolName: iconName, accessibilityDescription: nil) ?? createFallbackIcon(iconName)
        } else {
            icon = createFallbackIcon(iconName)
        }
        
        iconCache[iconName] = icon
        return icon
    }
    
    private static func createFallbackIcon(_ iconName: String) -> NSImage {
        let image = NSImage(size: NSSize(width: Constants.iconSize, height: Constants.iconSize))
        image.lockFocus()
        
        NSColor.labelColor.set()
        
        switch iconName {
        case "music.note":
            let path = NSBezierPath(ovalIn: NSRect(x: 6, y: 2, width: 4, height: 4))
            path.fill()
            let line = NSBezierPath()
            line.move(to: NSPoint(x: 10, y: 6))
            line.line(to: NSPoint(x: 10, y: 12))
            line.lineWidth = 1.5
            line.stroke()
            
        case "bluetooth":
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
            let screen = NSBezierPath(rect: NSRect(x: 3, y: 6, width: 10, height: 7))
            screen.fill()
            let base = NSBezierPath(rect: NSRect(x: 6, y: 4, width: 4, height: 2))
            base.fill()
            
        case "speaker.wave.3":
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
            for i in 0..<3 {
                let bar = NSBezierPath(rect: NSRect(x: 4 + i * 3, y: 4 + i * 2, width: 2, height: 8 - i * 2))
                bar.fill()
            }
            
        default:
            let path = NSBezierPath(ovalIn: NSRect(x: 4, y: 4, width: 8, height: 8))
            path.fill()
        }
        
        image.unlockFocus()
        return image
    }
}

// MARK: - Main Controller
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
    
    init(statusItem: NSStatusItem) {
        self.statusItem = statusItem
        super.init()
        
        setupStatusItem()
        updateIcon()
        
        bonjourService = BonjourService()
        bonjourService.delegate = self
        
        webSocketService = WebSocketService()
        webSocketService.delegate = self
        
        volumeController.activeMenu = activeMenu
    }
    
    private func setupStatusItem() {
        statusItem.button?.title = "🎵"
        statusItem.button?.target = self
        statusItem.button?.action = #selector(menuButtonClicked)
    }
    
    private func updateIcon() {
        DispatchQueue.main.async { [weak self] in
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
            createConnectedMenu(menu)
        } else {
            createDisconnectedMenu(menu)
        }
        
        activeMenu = menu
        volumeController.activeMenu = menu
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + Constants.menuCloseCheckDelay) { [weak self] in
            if self?.statusItem.menu == nil {
                self?.handleMenuClosed()
            }
        }
    }
    
    private func handleMenuClosed() {
        volumeController.forceSendPendingVolume()
        volumeController.cleanup()
        activeMenu = nil
        volumeController.activeMenu = nil
    }
    
    private func createConnectedMenu(_ menu: NSMenu) {
        guard let state = currentState else {
            createConnectedMenuWithDefaults(menu)
            return
        }
        
        // Sources audio
        menu.addItem(UIFactory.createCircularItem(
            title: "Spotify",
            iconName: "music.note",
            isActive: state.activeSource == "librespot",
            target: self,
            action: #selector(sourceClicked),
            representedObject: "librespot"
        ))
        
        menu.addItem(UIFactory.createCircularItem(
            title: "Bluetooth",
            iconName: "bluetooth",
            isActive: state.activeSource == "bluetooth",
            target: self,
            action: #selector(sourceClicked),
            representedObject: "bluetooth"
        ))
        
        menu.addItem(UIFactory.createCircularItem(
            title: "macOS",
            iconName: "desktopcomputer",
            isActive: state.activeSource == "roc",
            target: self,
            action: #selector(sourceClicked),
            representedObject: "roc"
        ))
        
        menu.addItem(NSMenuItem.separator())
        
        // Volume
        let volumeHeaderItem = NSMenuItem(title: "Volume", action: nil, keyEquivalent: "")
        volumeHeaderItem.isEnabled = false
        menu.addItem(volumeHeaderItem)
        
        if let volume = currentVolume {
            let sliderItem = NSMenuItem()
            let sliderView = UIFactory.createVolumeSlider(
                volume: volume.volume,
                target: self,
                action: #selector(volumeChanged)
            )
            sliderItem.view = sliderView
            menu.addItem(sliderItem)
            
            // Configurer le contrôleur de volume
            if let slider = sliderView.subviews.first as? NSSlider {
                volumeController.setVolumeSlider(slider)
            }
        }
        
        menu.addItem(NSMenuItem.separator())
        
        // Toggles
        menu.addItem(UIFactory.createCircularItem(
            title: "Multiroom",
            iconName: "speaker.wave.3",
            isActive: state.multiroomEnabled,
            target: self,
            action: #selector(toggleClicked),
            representedObject: "multiroom"
        ))
        
        menu.addItem(UIFactory.createCircularItem(
            title: "Égaliseur",
            iconName: "slider.horizontal.3",
            isActive: state.equalizerEnabled,
            target: self,
            action: #selector(toggleClicked),
            representedObject: "equalizer"
        ))
    }
    
    private func createConnectedMenuWithDefaults(_ menu: NSMenu) {
        menu.addItem(UIFactory.createCircularItem(
            title: "Spotify",
            iconName: "music.note",
            isActive: true,
            target: self,
            action: #selector(sourceClicked),
            representedObject: "librespot"
        ))
        
        menu.addItem(UIFactory.createCircularItem(
            title: "Bluetooth",
            iconName: "bluetooth",
            isActive: false,
            target: self,
            action: #selector(sourceClicked),
            representedObject: "bluetooth"
        ))
        
        menu.addItem(UIFactory.createCircularItem(
            title: "macOS",
            iconName: "desktopcomputer",
            isActive: false,
            target: self,
            action: #selector(sourceClicked),
            representedObject: "roc"
        ))
        
        menu.addItem(NSMenuItem.separator())
        
        let volumeItem = NSMenuItem(title: "Volume", action: nil, keyEquivalent: "")
        volumeItem.isEnabled = false
        menu.addItem(volumeItem)
        
        menu.addItem(NSMenuItem.separator())
        
        menu.addItem(UIFactory.createCircularItem(
            title: "Multiroom",
            iconName: "speaker.wave.3",
            isActive: false,
            target: self,
            action: #selector(toggleClicked),
            representedObject: "multiroom"
        ))
        
        menu.addItem(UIFactory.createCircularItem(
            title: "Égaliseur",
            iconName: "slider.horizontal.3",
            isActive: false,
            target: self,
            action: #selector(toggleClicked),
            representedObject: "equalizer"
        ))
    }
    
    private func createDisconnectedMenu(_ menu: NSMenu) {
        let item = NSMenuItem(title: "Sonoak n'est pas allumé", action: nil, keyEquivalent: "")
        item.isEnabled = false
        menu.addItem(item)
    }
    
    @objc private func sourceClicked(_ sender: NSMenuItem) {
        guard let apiService = apiService,
              let sourceId = sender.representedObject as? String else { return }
        
        Task {
            do {
                try await apiService.changeSource(sourceId)
            } catch {
                print("❌ Erreur changement source: \(error)")
            }
        }
    }
    
    @objc private func toggleClicked(_ sender: NSMenuItem) {
        guard let apiService = apiService,
              let toggleType = sender.representedObject as? String else { return }
        
        Task {
            do {
                if toggleType == "multiroom" {
                    let newState = !(currentState?.multiroomEnabled ?? false)
                    try await apiService.setMultiroom(newState)
                } else if toggleType == "equalizer" {
                    let newState = !(currentState?.equalizerEnabled ?? false)
                    try await apiService.setEqualizer(newState)
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
        let maxAttempts = Constants.maxReconnectAttempts
        let apiService = OakOSAPIService(host: host, port: port)
        
        Task { @MainActor in
            do {
                _ = try await apiService.fetchState()
                self.connectToOakOS(name: name, host: host, port: port)
            } catch {
                if attempt < maxAttempts {
                    DispatchQueue.main.asyncAfter(deadline: .now() + Constants.reconnectDelay) { [weak self] in
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
        
        volumeController.cleanup()
        webSocketService.disconnect()
        
        if let menu = activeMenu {
            updateMenuInRealTime(menu)
        }
    }
}

// MARK: - WebSocketServiceDelegate
extension MenuBarController {
    func didReceiveStateUpdate(_ state: OakOSState) {
        currentState = state
        
        if let menu = activeMenu {
            updateMenuInRealTime(menu)
        }
    }
    
    func didReceiveVolumeUpdate(_ volume: VolumeStatus) {
        currentVolume = volume
        volumeController.setCurrentVolume(volume)
        volumeController.updateSliderFromWebSocket(volume.volume)
        
        if let menu = activeMenu {
            updateMenuInRealTimeExceptVolume(menu)
        }
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
            createConnectedMenu(menu)
        } else {
            createDisconnectedMenu(menu)
        }
    }
    
    private func updateMenuInRealTimeExceptVolume(_ menu: NSMenu) {
        // Ne pas recréer le menu pour les changements de volume
    }
}

// MARK: - Helper Classes
class ClickableView: NSView {
    var clickHandler: (() -> Void)?
    
    override func mouseDown(with event: NSEvent) {
        clickHandler?()
    }
    
    override func hitTest(_ point: NSPoint) -> NSView? {
        return bounds.contains(point) ? self : nil
    }
}

class MenuInteractionView: NSView {
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
    }
    
    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
    }
    
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
    }
    
    override var acceptsFirstResponder: Bool {
        return true
    }
    
    override func becomeFirstResponder() -> Bool {
        return true
    }
    
    override func resignFirstResponder() -> Bool {
        return true
    }
}
