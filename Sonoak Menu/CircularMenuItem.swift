import AppKit

// MARK: - Menu Item Configuration
struct MenuItemConfig {
    let title: String
    let iconName: String
    let isActive: Bool
    let target: AnyObject
    let action: Selector
    let representedObject: Any?
}

// MARK: - Circular Menu Item Component
class CircularMenuItem {
    // MARK: - Constants
    private static let iconSize: CGFloat = 16
    private static let circleSize: CGFloat = 26
    private static let circleMargin: CGFloat = 3
    private static let containerWidth: CGFloat = 200
    private static let containerHeight: CGFloat = 32
    private static let textLeftMargin: CGFloat = 46
    private static let textWidth: CGFloat = 140
    private static let textHeight: CGFloat = 16
    private static let textTopMargin: CGFloat = 8
    private static let circleLeftMargin: CGFloat = 14
    
    // MARK: - Public Interface
    static func create(with config: MenuItemConfig) -> NSMenuItem {
        let item = NSMenuItem()
        item.target = config.target
        item.action = config.action
        item.representedObject = config.representedObject
        
        let containerView = createContainerView(config: config, menuItem: item)
        item.view = containerView
        
        return item
    }
    
    // MARK: - Private Methods
    private static func createContainerView(config: MenuItemConfig, menuItem: NSMenuItem) -> NSView {
        let containerView = HoverableView(frame: NSRect(
            x: 0,
            y: 0,
            width: containerWidth,
            height: containerHeight
        ))
        
        // Capturer les valeurs nécessaires pour la closure
        let target = config.target
        let action = config.action
        
        // Gérer le clic
        containerView.clickHandler = { [weak target] in
            _ = target?.perform(action, with: menuItem)
        }
        
        // Configurer le background hover avec marges
        containerView.configureHoverBackground(leftMargin: 5, rightMargin: 5)
        
        // Ajouter le cercle avec l'icône
        let circleView = createCircleView(config: config)
        containerView.addSubview(circleView)
        
        // Ajouter le texte
        let textField = createTextField(config: config)
        containerView.addSubview(textField)
        
        return containerView
    }
    
    private static func createCircleView(config: MenuItemConfig) -> NSView {
        let circleView = NSView(frame: NSRect(
            x: circleLeftMargin,
            y: circleMargin,
            width: circleSize,
            height: circleSize
        ))
        
        circleView.wantsLayer = true
        circleView.layer?.cornerRadius = circleSize / 2
        
        // Appliquer la couleur selon l'état
        applyCircleColor(to: circleView, isActive: config.isActive)
        
        // Ajouter l'icône
        let iconView = createIconView(config: config)
        circleView.addSubview(iconView)
        
        return circleView
    }
    
    private static func createIconView(config: MenuItemConfig) -> NSImageView {
        let iconView = NSImageView(frame: NSRect(
            x: (circleSize - iconSize) / 2,
            y: (circleSize - iconSize) / 2,
            width: iconSize,
            height: iconSize
        ))
        
        iconView.image = IconProvider.getIcon(config.iconName)
        iconView.contentTintColor = config.isActive ? NSColor.white : NSColor.secondaryLabelColor
        
        return iconView
    }
    
    private static func createTextField(config: MenuItemConfig) -> NSTextField {
        let textField = NSTextField(labelWithString: config.title)
        textField.font = NSFont.menuFont(ofSize: 13)
        textField.textColor = NSColor.labelColor
        textField.frame = NSRect(
            x: textLeftMargin,
            y: textTopMargin,
            width: textWidth,
            height: textHeight
        )
        textField.isEditable = false
        textField.isBordered = false
        textField.backgroundColor = NSColor.clear
        
        return textField
    }
    
    private static func applyCircleColor(to circleView: NSView, isActive: Bool) {
        if isActive {
            if #available(macOS 10.14, *) {
                circleView.layer?.backgroundColor = NSColor.controlAccentColor.cgColor
            } else {
                circleView.layer?.backgroundColor = NSColor.systemBlue.cgColor
            }
        } else {
            // Restaurer la couleur originale des cercles inactifs
            circleView.layer?.backgroundColor = NSColor.tertiaryLabelColor.cgColor
        }
    }
}

// MARK: - Icon Provider (repris du code existant)
class IconProvider {
    private static var iconCache: [String: NSImage] = [:]
    
    static func getIcon(_ iconName: String) -> NSImage {
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
        let size = CGSize(width: 16, height: 16)
        let image = NSImage(size: size)
        
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

// MARK: - Hoverable View
class HoverableView: NSView {
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
    }
    
    func configureHoverBackground(leftMargin: CGFloat, rightMargin: CGFloat) {
        // Créer le layer pour le background hover
        hoverBackgroundLayer = CALayer()
        hoverBackgroundLayer?.frame = NSRect(
            x: leftMargin,
            y: 0,
            width: bounds.width - leftMargin - rightMargin,
            height: bounds.height
        )
        hoverBackgroundLayer?.cornerRadius = 6
        hoverBackgroundLayer?.backgroundColor = NSColor.clear.cgColor
        
        layer?.insertSublayer(hoverBackgroundLayer!, at: 0)
    }
    
    private func setupTrackingArea() {
        let options: NSTrackingArea.Options = [
            .mouseEnteredAndExited,
            .activeInKeyWindow
        ]
        
        trackingArea = NSTrackingArea(
            rect: bounds,
            options: options,
            owner: self,
            userInfo: nil
        )
        
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
        
        // Couleur SwiftUI native plus subtile pour dark mode
        let hoverColor: NSColor
        if #available(macOS 10.14, *) {
            hoverColor = NSColor.tertiaryLabelColor
        } else {
            hoverColor = NSColor.lightGray.withAlphaComponent(0.2)
        }
        
        // Désactiver les animations implicites
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        hoverBackgroundLayer?.backgroundColor = hoverColor.cgColor
        CATransaction.commit()
    }
    
    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        
        // Désactiver les animations implicites
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

// MARK: - Clickable View (repris du code existant)
class ClickableView: NSView {
    var clickHandler: (() -> Void)?
    
    override func mouseDown(with event: NSEvent) {
        clickHandler?()
    }
    
    override func hitTest(_ point: NSPoint) -> NSView? {
        return bounds.contains(point) ? self : nil
    }
}
