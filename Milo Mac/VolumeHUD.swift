import AppKit
import Foundation

class VolumeHUD {
    private var window: NSWindow?
    private var containerView: NSVisualEffectView?
    private var fillView: NSView?
    private var volumeLabel: NSTextField?
    private var hideTimer: Timer?
    
    private let windowWidth: CGFloat = 472
    private let windowHeight: CGFloat = 64
    private let sliderHeight: CGFloat = 32
    private let cornerRadius: CGFloat = 32
    
    init() {
        setupWindow()
        setupViews()
    }
    
    private func setupWindow() {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: windowWidth, height: windowHeight),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        
        guard let window = window else { return }
        
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.maximumWindow)) + 1)
        window.backgroundColor = NSColor.clear
        window.isOpaque = false
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .stationary]
        
        // Positionner au centre en haut, mais décalé vers le haut pour l'animation
        if let screen = NSScreen.main {
            let screenRect = screen.visibleFrame
            let windowRect = NSRect(
                x: screenRect.midX - windowWidth / 2,
                y: screenRect.maxY - windowHeight - 20,
                width: windowWidth,
                height: windowHeight
            )
            window.setFrame(windowRect, display: false)
        }
        
        // Initialement invisible et décalé vers le haut
        window.alphaValue = 0
    }
    
    private func setupViews() {
        guard let window = window else { return }
        
        // Container avec effet blur natif macOS
        containerView = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: windowWidth, height: windowHeight))
        guard let containerView = containerView else { return }
        
        // Configuration de l'effet blur
        containerView.material = .hudWindow
        containerView.blendingMode = .behindWindow
        containerView.state = .active
        
        // Styling du container
        containerView.wantsLayer = true
        containerView.layer?.cornerRadius = cornerRadius
        containerView.layer?.borderWidth = 2
        containerView.layer?.borderColor = NSColor(white: 1.0, alpha: 0.1).cgColor
        
        window.contentView = containerView
        
        // Slider background - centré dans le container
        let sliderContainer = NSView(frame: NSRect(
            x: 16, y: (windowHeight - sliderHeight) / 2,
            width: windowWidth - 32,
            height: sliderHeight
        ))
        sliderContainer.wantsLayer = true
        sliderContainer.layer?.backgroundColor = NSColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.16).cgColor
        sliderContainer.layer?.cornerRadius = sliderHeight / 2
        
        containerView.addSubview(sliderContainer)
        
        // Fill view
        fillView = NSView(frame: NSRect(x: 0, y: 0, width: 0, height: sliderHeight))
        guard let fillView = fillView else { return }
        
        fillView.wantsLayer = true
        fillView.layer?.backgroundColor = NSColor(red: 0.09, green: 0.098, blue: 0.09, alpha: 1.0).cgColor
        fillView.layer?.cornerRadius = sliderHeight / 2
        
        sliderContainer.addSubview(fillView)
        
        // Volume label avec Space Mono
        volumeLabel = NSTextField(labelWithString: "50 %")
        guard let volumeLabel = volumeLabel else { return }
        
        // Essayer d'utiliser Space Mono, sinon fallback sur SF Mono
        let spaceMono = NSFont(name: "Space Mono", size: 16) ??
                       NSFont.monospacedSystemFont(ofSize: 16, weight: .regular)
        volumeLabel.font = spaceMono
        
        // Appliquer le letter-spacing de -2%
        let attributedString = NSMutableAttributedString(string: "50 %")
        attributedString.addAttribute(.kern, value: -0.32, range: NSRange(location: 0, length: attributedString.length)) // -2% de 16px = -0.32
        volumeLabel.attributedStringValue = attributedString
        
        volumeLabel.textColor = NSColor.secondaryLabelColor
        volumeLabel.frame = NSRect(x: 14, y: (sliderHeight - 16) / 2, width: 80, height: 17.5)
        volumeLabel.alignment = .left
        volumeLabel.backgroundColor = NSColor.clear
        volumeLabel.isBordered = false
        
        sliderContainer.addSubview(volumeLabel)
        
        // Initialiser la fenêtre comme invisible (pas de décalage initial)
        window.alphaValue = 0
    }
    
    func show(volume: Int) {
        guard let window = window else { return }
        
        // Mettre à jour le volume
        updateVolume(volume)
        
        // Annuler le timer précédent
        hideTimer?.invalidate()
        
        // Montrer la fenêtre
        window.orderFrontRegardless()
        
        // Animation d'entrée avec fade uniquement
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            
            window.animator().alphaValue = 1.0
        }
        
        scheduleHide()
    }
    
    private func updateVolume(_ volume: Int) {
        guard let fillView = fillView,
              let volumeLabel = volumeLabel else { return }
        
        // Mettre à jour le texte avec Space Mono et letter-spacing
        let volumeText = "\(volume) %"
        let spaceMono = NSFont(name: "Space Mono", size: 16) ??
                       NSFont.monospacedSystemFont(ofSize: 16, weight: .regular)
        
        let attributedString = NSMutableAttributedString(string: volumeText)
        attributedString.addAttribute(.font, value: spaceMono, range: NSRange(location: 0, length: attributedString.length))
        attributedString.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: NSRange(location: 0, length: attributedString.length))
        attributedString.addAttribute(.kern, value: -0.32, range: NSRange(location: 0, length: attributedString.length)) // -2% de 16px = -0.32
        
        volumeLabel.attributedStringValue = attributedString
        
        let sliderWidth = windowWidth - 64
        let isCircleMode = volume < 10
        
        let fillWidth: CGFloat
        let fillX: CGFloat
        
        if isCircleMode {
            // Mode cercle : largeur fixe de 32px, position qui se décale vers la gauche
            fillWidth = 32
            // Calculer le décalage : plus le volume est bas, plus c'est décalé à gauche
            let maxLeftOffset: CGFloat = 32
            let volumeRatio = CGFloat(volume) / 10.0 // ratio entre 0 et 1 pour volumes 0-10
            fillX = -maxLeftOffset + (volumeRatio * maxLeftOffset)
        } else {
            // Mode normal : largeur proportionnelle au volume
            fillWidth = (CGFloat(volume) / 100.0) * sliderWidth
            fillX = 0
        }
        
        // Animation fluide de la barre
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            
            fillView.animator().frame = NSRect(
                x: fillX,
                y: 0,
                width: fillWidth,
                height: sliderHeight
            )
        }
    }
    
    private func scheduleHide() {
        hideTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { [weak self] _ in
            self?.hide()
        }
    }
    
    private func hide() {
        guard let window = window else { return }
        
        hideTimer?.invalidate()
        hideTimer = nil
        
        // Animation de sortie avec fade uniquement
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.3
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            
            window.animator().alphaValue = 0.0
            
        }) {
            // Cacher la fenêtre après l'animation
            window.orderOut(nil)
        }
    }
    
    // Fonction pour prolonger l'affichage et mettre à jour le volume
    func extendDisplay(volume: Int) {
        updateVolume(volume)
        scheduleHide()
    }
    
    deinit {
        hideTimer?.invalidate()
        window?.orderOut(nil)
    }
}
