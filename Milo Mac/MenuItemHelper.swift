import AppKit

// MARK: - Menu Item Helper
class MenuItemHelper {
    
    // MARK: - Simple Menu Items
    static func createSimpleMenuItem(title: String, target: AnyObject, action: Selector) -> NSMenuItem {
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
    
    static func createSimpleToggleItem(title: String, isEnabled: Bool, target: AnyObject, action: Selector) -> NSMenuItem {
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
