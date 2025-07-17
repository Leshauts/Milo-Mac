import AppKit

// MARK: - Native Volume Slider
class NativeVolumeSlider: NSSlider {
    private let trackHeight: CGFloat = 22
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupSlider()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupSlider()
    }
    
    private func setupSlider() {
        sliderType = .linear
        isContinuous = true
        controlSize = .regular
        
        // Remplacer la cell par notre cell personnalisée
        cell = NativeVolumeSliderCell()
        
        // Configuration de base
        minValue = 0
        maxValue = 100
        
        if #available(macOS 10.14, *) {
            trackFillColor = NSColor.white
        }
    }
    
    override func awakeFromNib() {
        super.awakeFromNib()
        setupSlider()
    }
    
    override func draw(_ dirtyRect: NSRect) {
        // Dessiner notre slider personnalisé
        drawCustomSlider(in: bounds)
    }
    
    private func drawCustomSlider(in rect: NSRect) {
        // Calculer la position du track centré verticalement
        let trackY = rect.midY - trackHeight / 2
        let trackRect = NSRect(x: rect.minX + 5, y: trackY, width: rect.width - 10, height: trackHeight)
        
        // Dessiner le track de fond (gris clair)
        let trackPath = NSBezierPath(roundedRect: trackRect, xRadius: trackHeight / 2, yRadius: trackHeight / 2)
        NSColor.quaternaryLabelColor.setFill()
        trackPath.fill()
        
        // Calculer la largeur du fill basé sur la valeur
        let fillWidth = trackRect.width * CGFloat((doubleValue - minValue) / (maxValue - minValue))
        
        if fillWidth > 0 {
            // Dessiner le fill blanc
            let fillRect = NSRect(x: trackRect.minX, y: trackRect.minY, width: fillWidth, height: trackRect.height)
            let fillPath = NSBezierPath(roundedRect: fillRect, xRadius: trackHeight / 2, yRadius: trackHeight / 2)
            NSColor.white.setFill()
            fillPath.fill()
            
            // Ajouter l'icône volume à l'intérieur du fill
            drawVolumeIcon(in: fillRect)
        }
    }
    
    private func drawVolumeIcon(in rect: NSRect) {
        // Dessiner une icône de volume simple à gauche du fill
        let iconSize: CGFloat = 12
        let iconX = rect.minX + 8
        let iconY = rect.midY - iconSize / 2
        let iconRect = NSRect(x: iconX, y: iconY, width: iconSize, height: iconSize)
        
        // Vérifier qu'on a assez d'espace pour l'icône
        guard rect.width > iconSize + 16 else { return }
        
        NSColor.black.setFill()
        
        // Dessiner l'icône du haut-parleur
        let speakerPath = NSBezierPath()
        speakerPath.move(to: NSPoint(x: iconRect.minX, y: iconRect.minY + 3))
        speakerPath.line(to: NSPoint(x: iconRect.minX + 3, y: iconRect.minY + 3))
        speakerPath.line(to: NSPoint(x: iconRect.minX + 6, y: iconRect.minY))
        speakerPath.line(to: NSPoint(x: iconRect.minX + 6, y: iconRect.maxY))
        speakerPath.line(to: NSPoint(x: iconRect.minX + 3, y: iconRect.maxY - 3))
        speakerPath.line(to: NSPoint(x: iconRect.minX, y: iconRect.maxY - 3))
        speakerPath.close()
        speakerPath.fill()
        
        // Ajouter les ondes sonores
        let wave1 = NSBezierPath()
        wave1.move(to: NSPoint(x: iconRect.minX + 8, y: iconRect.minY + 4))
        wave1.curve(to: NSPoint(x: iconRect.minX + 8, y: iconRect.maxY - 4),
                   controlPoint1: NSPoint(x: iconRect.minX + 10, y: iconRect.minY + 4),
                   controlPoint2: NSPoint(x: iconRect.minX + 10, y: iconRect.maxY - 4))
        wave1.lineWidth = 1
        wave1.stroke()
    }
    
    override func mouseDown(with event: NSEvent) {
        // Gérer le clic pour ajuster la valeur
        let point = convert(event.locationInWindow, from: nil)
        let trackRect = NSRect(x: 5, y: bounds.midY - trackHeight / 2, width: bounds.width - 10, height: trackHeight)
        
        if trackRect.contains(point) {
            let relativeX = point.x - trackRect.minX
            let percentage = relativeX / trackRect.width
            let newValue = minValue + (maxValue - minValue) * Double(percentage)
            
            doubleValue = max(minValue, min(maxValue, newValue))
            
            // Envoyer l'action
            if let target = target, let action = action {
                NSApp.sendAction(action, to: target, from: self)
            }
            
            needsDisplay = true
        }
    }
    
    override func mouseDragged(with event: NSEvent) {
        // Même logique que mouseDown pour le drag
        mouseDown(with: event)
    }
}

// MARK: - Custom Slider Cell (simplifiée)
class NativeVolumeSliderCell: NSSliderCell {
    override func drawBar(inside rect: NSRect, flipped: Bool) {
        // Ne rien dessiner ici, c'est géré par la vue
    }
    
    override func drawKnob(_ knobRect: NSRect) {
        // Ne pas dessiner le knob traditionnel
    }
}
