import SwiftUI
import AppKit

// MARK: - Menu Item Factory
class MenuItemFactory {
    private static let iconSize: CGFloat = 16
    private static let circleSize: CGFloat = 26
    private static let circleMargin: CGFloat = 3
    private static let containerWidth: CGFloat = 200
    private static let containerHeight: CGFloat = 32
    
    // MARK: - Volume Section
    static func createVolumeSection(volume: Int, target: AnyObject, action: Selector) -> [NSMenuItem] {
        var items: [NSMenuItem] = []
        
        // Header "Volume"
        let header = createVolumeHeader()
        items.append(header)
        
        // Slider
        let sliderItem = createVolumeSlider(volume: volume, target: target, action: action)
        items.append(sliderItem)
        
        // Séparateur
        items.append(NSMenuItem.separator())
        
        return items
    }
    
    // MARK: - Disconnected State
    static func createDisconnectedItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Sonoak n'est pas allumé", action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }
    
    private static func createSecondaryHeader(title: String) -> NSMenuItem {
        let item = NSMenuItem()
        let headerView = NSView(frame: NSRect(x: 0, y: 0, width: containerWidth, height: 22))
        
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = NSFont.systemFont(ofSize: 12, weight: .bold)
        titleLabel.textColor = NSColor.secondaryLabelColor
        titleLabel.frame = NSRect(x: 12, y: 2, width: 160, height: 16)
        
        headerView.addSubview(titleLabel)
        item.view = headerView
        
        return item
    }
    
    private static func createVolumeHeader() -> NSMenuItem {
        let item = NSMenuItem()
        let headerView = NSView(frame: NSRect(x: 0, y: 0, width: containerWidth, height: 28))
        
        let titleLabel = NSTextField(labelWithString: "Volume")
        titleLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = NSColor.labelColor
        titleLabel.frame = NSRect(x: 12, y: 4, width: 160, height: 16)
        
        headerView.addSubview(titleLabel)
        item.view = headerView
        
        return item
    }
    
    private static func createVolumeSlider(volume: Int, target: AnyObject, action: Selector) -> NSMenuItem {
        let item = NSMenuItem()
        
        // Container avec la largeur complète
        let containerView = MenuInteractionView(frame: NSRect(x: 0, y: 0, width: containerWidth, height: 31))
        
        // Slider avec marges de 14px de chaque côté (même largeur que les séparateurs)
        let slider = NativeVolumeSlider(frame: NSRect(x: 14, y: 5, width: containerWidth - 28, height: 22))
        slider.doubleValue = Double(volume)
        slider.target = target
        slider.action = action
        
        containerView.addSubview(slider)
        item.view = containerView
        
        return item
    }
    
    // MARK: - Audio Sources Section
    static func createAudioSourcesSection(state: OakOSState?, target: AnyObject, action: Selector) -> [NSMenuItem] {
        var items: [NSMenuItem] = []
        
        // Titre secondaire "Sortie"
        let sortieHeader = createSecondaryHeader(title: "Sortie")
        items.append(sortieHeader)
        
        let activeSource = state?.activeSource ?? "none"
        
        items.append(CircularMenuItem.create(with: MenuItemConfig(
            title: "Spotify",
            iconName: "music.note",
            isActive: activeSource == "librespot",
            target: target,
            action: action,
            representedObject: "librespot"
        )))
        
        items.append(CircularMenuItem.create(with: MenuItemConfig(
            title: "Bluetooth",
            iconName: "bluetooth",
            isActive: activeSource == "bluetooth",
            target: target,
            action: action,
            representedObject: "bluetooth"
        )))
        
        items.append(CircularMenuItem.create(with: MenuItemConfig(
            title: "macOS",
            iconName: "desktopcomputer",
            isActive: activeSource == "roc",
            target: target,
            action: action,
            representedObject: "roc"
        )))
        
        items.append(NSMenuItem.separator())
        
        return items
    }
    
    // MARK: - System Controls Section
    static func createSystemControlsSection(state: OakOSState?, target: AnyObject, action: Selector) -> [NSMenuItem] {
        var items: [NSMenuItem] = []
        
        // Titre secondaire "Fonctionnalités"
        let featuresHeader = createSecondaryHeader(title: "Fonctionnalités")
        items.append(featuresHeader)
        
        items.append(CircularMenuItem.create(with: MenuItemConfig(
            title: "Multiroom",
            iconName: "speaker.wave.3",
            isActive: state?.multiroomEnabled ?? false,
            target: target,
            action: action,
            representedObject: "multiroom"
        )))
        
        items.append(CircularMenuItem.create(with: MenuItemConfig(
            title: "Égaliseur",
            iconName: "slider.horizontal.3",
            isActive: state?.equalizerEnabled ?? false,
            target: target,
            action: action,
            representedObject: "equalizer"
        )))
        
        return items
    }
}

// MARK: - Menu Interaction View
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
