import SwiftUI
import AppKit
import ServiceManagement

class MenuBarController: NSObject, MiloConnectionManagerDelegate {
    // MARK: - Properties
    private var statusItem: NSStatusItem
    private var connectionManager: MiloConnectionManager!
    private var hotkeyManager: GlobalHotkeyManager?
    private let volumeController = VolumeController()
    
    // MARK: - State
    private var isMiloConnected = false
    private var currentState: MiloState?
    private var currentVolume: VolumeStatus?
    private var isMenuOpen = false
    
    // MARK: - UI State
    private var activeMenu: NSMenu?
    private var isPreferencesMenuActive = false
    
    // MARK: - Loading State
    private var loadingStates: [String: Bool] = [:]
    private var loadingTimers: [String: Timer] = [:]
    private var loadingStartTimes: [String: Date] = [:]
    private var loadingTarget: String?
    
    // MARK: - Constants
    private let loadingTimeoutDuration: TimeInterval = 15.0
    private let minimumLoadingDuration: TimeInterval = 1.0
    
    // MARK: - Initialization
    init(statusItem: NSStatusItem) {
        self.statusItem = statusItem
        super.init()
        
        setupStatusItem()
        setupConnectionManager()
        setupObservers()
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
        hotkeyManager = GlobalHotkeyManager(connectionManager: connectionManager, menuController: self)
        connectionManager.start()
    }
    
    private func setupObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleVolumeChangedViaHotkey),
            name: NSNotification.Name("VolumeChangedViaHotkey"),
            object: nil
        )
    }
    
    // MARK: - Public Interface
    func isMenuCurrentlyOpen() -> Bool {
        return isMenuOpen
    }
    
    // MARK: - Menu Display
    @objc private func menuButtonClicked() {
        statusItem.menu = nil
        
        guard let event = NSApp.currentEvent else {
            showMainMenu()
            return
        }
        
        if event.modifierFlags.contains(.option) {
            showPreferencesMenu()
        } else {
            showMainMenu()
        }
    }
    
    private func showMainMenu() {
        let menu = createMenu(isPreferences: false)
        displayMenu(menu)
    }
    
    private func showPreferencesMenu() {
        let menu = createMenu(isPreferences: true)
        displayMenu(menu)
    }
    
    private func createMenu(isPreferences: Bool) -> NSMenu {
        isMenuOpen = true
        
        let menu = NSMenu()
        menu.font = NSFont.menuFont(ofSize: 13)
        
        if isMiloConnected {
            buildConnectedMenu(menu, isPreferences: isPreferences)
        } else {
            buildDisconnectedMenu(menu, isPreferences: isPreferences)
        }
        
        activeMenu = menu
        isPreferencesMenuActive = isPreferences
        volumeController.activeMenu = menu
        
        return menu
    }
    
    private func displayMenu(_ menu: NSMenu) {
        NSApp.activate(ignoringOtherApps: true)
        statusItem.menu = menu
        
        statusItem.button?.performClick(nil)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.statusItem.menu = nil
            self?.monitorMenuClosure()
        }
        
        if isMiloConnected {
            refreshMenuData()
        }
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
    
    private func handleMenuClosed() {
        isMenuOpen = false
        volumeController.cleanup()
        activeMenu = nil
        isPreferencesMenuActive = false
        volumeController.activeMenu = nil
    }
    
    // MARK: - Menu Building
    private func buildConnectedMenu(_ menu: NSMenu, isPreferences: Bool) {
        addVolumeSection(to: menu)
        addAudioSourcesSection(to: menu)
        addSystemControlsSection(to: menu)
        
        if isPreferences {
            addPreferencesSection(to: menu)
        }
    }
    
    private func buildDisconnectedMenu(_ menu: NSMenu, isPreferences: Bool) {
        let disconnectedItem = MenuItemFactory.createDisconnectedItem()
        menu.addItem(disconnectedItem)
        
        if isPreferences {
            menu.addItem(NSMenuItem.separator())
            addPreferencesSection(to: menu, connected: false)
        }
    }
    
    private func addVolumeSection(to menu: NSMenu) {
        let volumeItems = MenuItemFactory.createVolumeSection(
            volume: currentVolume?.volume ?? 50,
            target: self,
            action: #selector(volumeChanged)
        )
        volumeItems.forEach { menu.addItem($0) }
        
        // Setup volume slider reference
        if let sliderItem = volumeItems.first(where: { $0.view is MenuInteractionView }),
           let sliderView = sliderItem.view as? MenuInteractionView,
           let slider = sliderView.subviews.first(where: { $0 is NSSlider }) as? NSSlider {
            volumeController.setVolumeSlider(slider)
        }
    }
    
    private func addAudioSourcesSection(to menu: NSMenu) {
        let sourceItems = MenuItemFactory.createAudioSourcesSection(
            state: currentState,
            loadingStates: loadingStates,
            loadingTarget: loadingTarget,
            target: self,
            action: #selector(sourceClicked)
        )
        sourceItems.forEach { menu.addItem($0) }
    }
    
    private func addSystemControlsSection(to menu: NSMenu) {
        let systemItems = MenuItemFactory.createSystemControlsSection(
            state: currentState,
            loadingStates: loadingStates,
            loadingTarget: loadingTarget,
            target: self,
            action: #selector(toggleClicked)
        )
        systemItems.forEach { menu.addItem($0) }
    }
    
    private func addPreferencesSection(to menu: NSMenu, connected: Bool = true) {
        menu.addItem(NSMenuItem.separator())
        
        if connected {
            addHotkeysToggle(to: menu)
            addVolumeDeltaConfig(to: menu)
        }
        
        addLaunchAtLoginToggle(to: menu)
        addQuitItem(to: menu)
    }
    
    private func addHotkeysToggle(to menu: NSMenu) {
        let hotkeysItem = MenuItemHelper.createSimpleToggleItem(
            title: "Raccourcis volume (⌥↑/↓)",
            isEnabled: hotkeyManager?.isCurrentlyMonitoring() ?? false,
            target: self,
            action: #selector(toggleGlobalHotkeys)
        )
        menu.addItem(hotkeysItem)
    }
    
    private func addVolumeDeltaConfig(to menu: NSMenu) {
        if let hotkeyManager = hotkeyManager {
            let deltaConfigItem = MenuItemFactory.createVolumeDeltaConfigItem(
                currentDelta: hotkeyManager.getVolumeDelta(),
                target: self,
                decreaseAction: #selector(decreaseVolumeDelta),
                increaseAction: #selector(increaseVolumeDelta)
            )
            menu.addItem(deltaConfigItem)
        }
    }
    
    private func addLaunchAtLoginToggle(to menu: NSMenu) {
        let launchAtLoginItem = MenuItemHelper.createSimpleToggleItem(
            title: "Démarrer au démarrage du Mac",
            isEnabled: isLaunchAtLoginEnabled(),
            target: self,
            action: #selector(toggleLaunchAtLogin)
        )
        menu.addItem(launchAtLoginItem)
    }
    
    private func addQuitItem(to menu: NSMenu) {
        let quitItem = MenuItemHelper.createSimpleMenuItem(
            title: "Quitter",
            target: self,
            action: #selector(quitApplication)
        )
        menu.addItem(quitItem)
    }
    
    // MARK: - Actions
    @objc private func volumeChanged(_ sender: NSSlider) {
        let newVolume = Int(sender.doubleValue)
        volumeController.handleVolumeChange(newVolume)
    }
    
    @objc private func sourceClicked(_ sender: NSMenuItem) {
        guard let sourceId = sender.representedObject as? String,
              let apiService = connectionManager.getAPIService() else { return }
        
        let activeSource = currentState?.activeSource ?? "none"
        guard activeSource != sourceId else { return }
        
        startLoading(for: sourceId, timeout: loadingTimeoutDuration)
        
        Task {
            do {
                try await apiService.changeSource(sourceId)
            } catch {
                await MainActor.run { self.stopLoading(for: sourceId) }
            }
        }
    }
    
    @objc private func toggleClicked(_ sender: NSMenuItem) {
        guard let toggleType = sender.representedObject as? String,
              let apiService = connectionManager.getAPIService() else { return }
        
        let currentlyEnabled = getCurrentToggleState(toggleType)
        let newState = !currentlyEnabled
        
        startLoading(for: toggleType, timeout: 10.0)
        
        Task {
            do {
                switch toggleType {
                case "multiroom":
                    try await apiService.setMultiroom(newState)
                case "equalizer":
                    try await apiService.setEqualizer(newState)
                default:
                    break
                }
            } catch {
                await MainActor.run { self.stopLoading(for: toggleType) }
            }
        }
    }
    
    @objc private func toggleGlobalHotkeys() {
        guard let hotkeyManager = hotkeyManager else { return }
        
        if hotkeyManager.isCurrentlyMonitoring() {
            hotkeyManager.stopMonitoring()
        } else {
            hotkeyManager.startMonitoring()
            schedulePermissionRechecks()
            scheduleUIUpdate()
        }
    }
    
    @objc private func decreaseVolumeDelta() {
        guard let hotkeyManager = hotkeyManager else { return }
        let newDelta = max(1, hotkeyManager.getVolumeDelta() - 1)
        hotkeyManager.setVolumeDelta(newDelta)
        updateVolumeDeltaInterface()
    }
    
    @objc private func increaseVolumeDelta() {
        guard let hotkeyManager = hotkeyManager else { return }
        let newDelta = min(10, hotkeyManager.getVolumeDelta() + 1)
        hotkeyManager.setVolumeDelta(newDelta)
        updateVolumeDeltaInterface()
    }
    
    @objc private func toggleLaunchAtLogin() {
        if #available(macOS 13.0, *) {
            toggleModernLaunchAtLogin()
        } else {
            toggleLegacyLaunchAtLogin()
        }
    }
    
    @objc private func quitApplication() {
        NSApplication.shared.terminate(nil)
    }
    
    // MARK: - Loading State Management
    private func startLoading(for identifier: String, timeout: TimeInterval) {
        guard loadingStates[identifier] != true else { return }
        
        loadingTarget = identifier
        loadingStartTimes[identifier] = Date()
        setLoadingState(for: identifier, isLoading: true)
        
        loadingTimers[identifier]?.invalidate()
        loadingTimers[identifier] = Timer.scheduledTimer(withTimeInterval: timeout, repeats: false) { _ in
            Task { @MainActor in self.stopLoading(for: identifier) }
        }
    }
    
    private func stopLoading(for identifier: String) {
        setLoadingState(for: identifier, isLoading: false)
        loadingTimers[identifier]?.invalidate()
        loadingTimers[identifier] = nil
        loadingStartTimes[identifier] = nil
        
        if loadingTarget == identifier {
            loadingTarget = nil
        }
        
        if let menu = activeMenu {
            updateMenuInRealTime(menu)
        }
    }
    
    private func setLoadingState(for identifier: String, isLoading: Bool) {
        guard loadingStates[identifier] != isLoading else { return }
        
        loadingStates[identifier] = isLoading
        
        if let menu = activeMenu {
            updateMenuInRealTime(menu)
        }
    }
    
    // MARK: - Helper Methods
    private func getCurrentToggleState(_ toggleType: String) -> Bool {
        switch toggleType {
        case "multiroom": return currentState?.multiroomEnabled ?? false
        case "equalizer": return currentState?.equalizerEnabled ?? false
        default: return false
        }
    }
    
    private func schedulePermissionRechecks() {
        guard let hotkeyManager = hotkeyManager else { return }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            hotkeyManager.recheckPermissions()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            hotkeyManager.recheckPermissions()
        }
    }
    
    private func scheduleUIUpdate() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            if let menu = self?.activeMenu {
                self?.updateMenuInRealTime(menu)
            }
        }
    }
    
    private func updateVolumeDeltaInterface() {
        guard let menu = activeMenu, isPreferencesMenuActive else { return }
        
        for item in menu.items {
            if let components = item.representedObject as? [String: NSView],
               let decreaseButton = components["decrease"] as? NSButton,
               let increaseButton = components["increase"] as? NSButton,
               let valueLabel = components["value"] as? NSTextField,
               let hotkeyManager = hotkeyManager {
                
                let currentDelta = hotkeyManager.getVolumeDelta()
                valueLabel.stringValue = "\(currentDelta)"
                decreaseButton.isEnabled = currentDelta > 1
                increaseButton.isEnabled = currentDelta < 10
                break
            }
        }
    }
    
    private func updateMenuInRealTime(_ menu: NSMenu) {
        CircularMenuItem.cleanupAllSpinners()
        menu.removeAllItems()
        
        if isMiloConnected {
            buildConnectedMenu(menu, isPreferences: isPreferencesMenuActive)
        } else {
            buildDisconnectedMenu(menu, isPreferences: isPreferencesMenuActive)
        }
    }
    
    private func updateIcon() {
        DispatchQueue.main.async { [weak self] in
            self?.statusItem.button?.alphaValue = self?.isMiloConnected == true ? 1.0 : 0.5
        }
    }
    
    private func isLaunchAtLoginEnabled() -> Bool {
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        } else {
            return false // Legacy method would be implemented here
        }
    }
    
    @available(macOS 13.0, *)
    private func toggleModernLaunchAtLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled {
                try service.unregister()
            } else {
                try service.register()
            }
        } catch {
            print("Error toggling launch at login: \(error)")
        }
    }
    
    private func toggleLegacyLaunchAtLogin() {
        let bundleIdentifier = Bundle.main.bundleIdentifier ?? ""
        let currentStatus = isLaunchAtLoginEnabled()
        SMLoginItemSetEnabled(bundleIdentifier as CFString, !currentStatus)
    }
    
    // MARK: - Data Refresh
    private func refreshMenuData() {
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
    
    private func refreshState() async {
        guard let apiService = connectionManager.getAPIService() else { return }
        
        do {
            let state = try await apiService.fetchState()
            await MainActor.run { self.currentState = state }
        } catch {
            // Handle error silently
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
            // Handle error silently
        }
    }
    
    @objc private func handleVolumeChangedViaHotkey(_ notification: Notification) {
        guard let volumeStatus = notification.object as? VolumeStatus else { return }
        
        currentVolume = volumeStatus
        volumeController.setCurrentVolume(volumeStatus)
        volumeController.updateSliderFromWebSocket(volumeStatus.volume)
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
        refreshMenuData()
    }
    
    func miloDidDisconnect() {
        hotkeyManager?.stopMonitoring()
        
        isMiloConnected = false
        updateIcon()
        
        clearState()
        volumeController.cleanup()
        
        if let menu = activeMenu {
            updateMenuInRealTime(menu)
        }
    }
    
    func didReceiveStateUpdate(_ state: MiloState) {
        currentState = state
        handleLoadingCompletion(for: state)
    }
    
    func didReceiveVolumeUpdate(_ volume: VolumeStatus) {
        currentVolume = volume
        volumeController.setCurrentVolume(volume)
        volumeController.updateSliderFromWebSocket(volume.volume)
    }
    
    private func clearState() {
        currentState = nil
        currentVolume = nil
        volumeController.apiService = nil
        
        // Clear all loading states
        loadingStates.keys.forEach { stopLoading(for: $0) }
        loadingTarget = nil
    }
    
    private func handleLoadingCompletion(for state: MiloState) {
        // Handle audio source loading completion
        if !state.isTransitioning {
            for (sourceId, isLoading) in loadingStates {
                if isLoading && state.activeSource == sourceId {
                    handleTimedLoadingCompletion(for: sourceId)
                }
            }
        }
        
        // Handle system toggle loading completion
        let systemToggles = ["multiroom", "equalizer"]
        for (toggleId, isLoading) in loadingStates {
            if isLoading && systemToggles.contains(toggleId) {
                handleTimedLoadingCompletion(for: toggleId)
            }
        }
        
        let hasActiveLoading = loadingStates.values.contains(true)
        if let menu = activeMenu, !hasActiveLoading {
            updateMenuInRealTime(menu)
        }
    }
    
    private func handleTimedLoadingCompletion(for identifier: String) {
        let startTime = loadingStartTimes[identifier] ?? Date()
        let elapsed = Date().timeIntervalSince(startTime)
        
        if elapsed >= minimumLoadingDuration {
            stopLoading(for: identifier)
        } else {
            let remainingTime = minimumLoadingDuration - elapsed
            DispatchQueue.main.asyncAfter(deadline: .now() + remainingTime) { [weak self] in
                self?.stopLoading(for: identifier)
            }
        }
    }
}
