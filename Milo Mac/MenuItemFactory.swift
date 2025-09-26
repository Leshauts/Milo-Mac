import SwiftUI
import AppKit

class MenuItemFactory {
    // MARK: - Constants
    private static let iconSize: CGFloat = 16
    private static let circleSize: CGFloat = 26
    private static let circleMargin: CGFloat = 3
    private static let containerWidth: CGFloat = 300
    private static let containerHeight: CGFloat = 32
    private static let sideMargin: CGFloat = 12
    private static let rightMargin: CGFloat = 14
    
    // MARK: - Volume Section
    static func createVolumeSection(volume: Int, target: AnyObject, action: Selector) -> [NSMenuItem] {
        return [
            createVolumeHeader(),
            createVolumeSlider(volume: volume, target: target, action: action),
            NSMenuItem.separator()
        ]
    }
    
    private static func createVolumeHeader() -> NSMenuItem {
        let item = NSMenuItem()
        let headerView = NSView(frame: NSRect(x: 0, y: 0, width: containerWidth, height: 28))
        
        let titleLabel = createLabel(text: "Volume de Milō", font: .systemFont(ofSize: 13, weight: .semibold))
        titleLabel.frame = NSRect(x: sideMargin, y: 4, width: 160, height: 16)
        
        headerView.addSubview(titleLabel)
        item.view = headerView
        
        return item
    }
    
    private static func createVolumeSlider(volume: Int, target: AnyObject, action: Selector) -> NSMenuItem {
        let item = NSMenuItem()
        let containerView = MenuInteractionView(frame: NSRect(x: 0, y: 0, width: containerWidth, height: 31))
        
        let slider = NativeVolumeSlider(frame: NSRect(x: rightMargin, y: 5, width: containerWidth - (rightMargin * 2), height: 22))
        slider.doubleValue = Double(volume)
        slider.target = target
        slider.action = action
        
        containerView.addSubview(slider)
        item.view = containerView
        
        return item
    }
    
    // MARK: - Configuration Items
    static func createVolumeDeltaConfigItem(currentDelta: Int, target: AnyObject, decreaseAction: Selector, increaseAction: Selector) -> NSMenuItem {
        let item = NSMenuItem()
        let containerView = MenuInteractionView(frame: NSRect(x: 0, y: 0, width: containerWidth, height: containerHeight))
        
        let titleLabel = createLabel(text: "Incrément volume", font: .menuFont(ofSize: 13))
        titleLabel.frame = NSRect(x: sideMargin, y: 8, width: 120, height: 16)
        
        let controls = createDeltaControls(currentDelta: currentDelta, target: target, decreaseAction: decreaseAction, increaseAction: increaseAction)
        
        containerView.addSubview(titleLabel)
        controls.forEach { containerView.addSubview($0) }
        
        item.view = containerView
        item.representedObject = [
            "decrease": controls[1], // decreaseButton
            "increase": controls[2], // increaseButton
            "value": controls[0]     // valueLabel
        ]
        
        return item
    }
    
    private static func createDeltaControls(currentDelta: Int, target: AnyObject, decreaseAction: Selector, increaseAction: Selector) -> [NSView] {
        let valueLabel = createLabel(text: "\(currentDelta)", font: .monospacedDigitSystemFont(ofSize: 13, weight: .medium))
        valueLabel.alignment = .center
        valueLabel.frame = NSRect(x: containerWidth - 66, y: 8, width: 24, height: 16)
        
        let decreaseButton = createDeltaButton(title: "−", target: target, action: decreaseAction, enabled: currentDelta > 1)
        decreaseButton.frame = NSRect(x: containerWidth - 94, y: 6, width: 24, height: 20)
        
        let increaseButton = createDeltaButton(title: "+", target: target, action: increaseAction, enabled: currentDelta < 10)
        increaseButton.frame = NSRect(x: containerWidth - 38, y: 6, width: 24, height: 20)
        
        return [valueLabel, decreaseButton, increaseButton]
    }
    
    private static func createDeltaButton(title: String, target: AnyObject, action: Selector, enabled: Bool) -> NSButton {
        let button = NSButton(frame: .zero)
        button.title = title
        button.font = NSFont.systemFont(ofSize: 14, weight: .medium)
        button.bezelStyle = .rounded
        button.controlSize = .mini
        button.target = target
        button.action = action
        button.isEnabled = enabled
        return button
    }
    
    // MARK: - Audio Sources Section (inchangé)
    static func createAudioSourcesSection(state: MiloState?, loadingStates: [String: Bool] = [:], target: AnyObject, action: Selector) -> [NSMenuItem] {
        var items: [NSMenuItem] = []
        
        items.append(createSecondaryHeader(title: "Sortie"))
        
        let activeSource = state?.activeSource ?? "none"
        let targetSource = state?.targetSource
        
        let sourceConfigs = [
            ("Spotify", "music.note", "librespot"),
            ("Bluetooth", "bluetooth", "bluetooth"),
            ("macOS", "desktopcomputer", "roc")
        ]
        
        for (title, iconName, sourceId) in sourceConfigs {
            let isLoading = (targetSource == sourceId)
            let isActive: Bool
            
            if let targetSource = targetSource {
                isActive = (sourceId == targetSource)
            } else {
                isActive = (activeSource == sourceId)
            }
            
            let config = MenuItemConfig(
                title: title,
                iconName: iconName,
                isActive: isActive,
                target: target,
                action: action,
                representedObject: sourceId
            )
            
            items.append(CircularMenuItem.createWithLoadingSupport(
                with: config,
                isLoading: isLoading,
                loadingIsActive: isLoading
            ))
        }
        
        items.append(NSMenuItem.separator())
        return items
    }
    
    // MARK: - CORRIGÉ : System Controls Section utilise loadingStates directement
    static func createSystemControlsSection(state: MiloState?, loadingStates: [String: Bool] = [:], target: AnyObject, action: Selector) -> [NSMenuItem] {
        var items: [NSMenuItem] = []
        
        items.append(createSecondaryHeader(title: "Fonctionnalités"))
        
        let systemConfigs = [
            ("Multiroom", "speaker.wave.3", "multiroom", state?.multiroomEnabled ?? false),
            ("Égaliseur", "slider.horizontal.3", "equalizer", state?.equalizerEnabled ?? false)
        ]
        
        for (title, iconName, toggleId, currentlyEnabled) in systemConfigs {
            // CORRECTION : Utiliser loadingStates directement au lieu de target_source
            let isLoading = loadingStates[toggleId] == true
            let isActive = isLoading || (!isLoading && currentlyEnabled)
            
            let config = MenuItemConfig(
                title: title,
                iconName: iconName,
                isActive: isActive,
                target: target,
                action: action,
                representedObject: toggleId
            )
            
            items.append(CircularMenuItem.createWithLoadingSupport(
                with: config,
                isLoading: isLoading,
                loadingIsActive: isLoading
            ))
        }
        
        return items
    }
    
    // MARK: - Disconnected State
    static func createDisconnectedItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Milō n'est pas allumé", action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }
    
    // MARK: - Helper Methods
    private static func createSecondaryHeader(title: String) -> NSMenuItem {
        let item = NSMenuItem()
        let headerView = NSView(frame: NSRect(x: 0, y: 0, width: containerWidth, height: 22))
        
        let titleLabel = createLabel(text: title, font: .systemFont(ofSize: 12, weight: .bold))
        titleLabel.textColor = NSColor.secondaryLabelColor
        titleLabel.frame = NSRect(x: sideMargin, y: 2, width: 160, height: 16)
        
        headerView.addSubview(titleLabel)
        item.view = headerView
        
        return item
    }
    
    private static func createLabel(text: String, font: NSFont) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = font
        label.textColor = NSColor.labelColor
        label.isEditable = false
        label.isBordered = false
        label.backgroundColor = NSColor.clear
        return label
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
