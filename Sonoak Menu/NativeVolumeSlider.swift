import AppKit

// MARK: - Native Volume Slider
class NativeVolumeSlider: NSSlider {
    private let trackHeight: CGFloat = 22
    private let fillHeight: CGFloat = 20
    private let thumbSize: CGFloat = 20
    
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
        drawCustomSlider(in: bounds)
    }
    
    private func drawCustomSlider(in rect: NSRect) {
        // Calculer la position du track centré verticalement - sans marge à gauche
        let trackY = rect.midY - trackHeight / 2
        let trackRect = NSRect(x: rect.minX, y: trackY, width: rect.width, height: trackHeight)
        
        // Dessiner le track de fond (même couleur que le hover de CircularMenuItem)
        let trackPath = NSBezierPath(roundedRect: trackRect, xRadius: trackHeight / 2, yRadius: trackHeight / 2)
        if #available(macOS 10.14, *) {
            NSColor.tertiaryLabelColor.setFill()
        } else {
            NSColor.lightGray.withAlphaComponent(0.2).setFill()
        }
        trackPath.fill()
        
        // Calculer le pourcentage de la valeur
        let percentage = CGFloat((doubleValue - minValue) / (maxValue - minValue))
        
        // Zone de l'icône - carrée/ronde de la même taille que fillHeight
        let iconZoneSize = fillHeight // 20px x 20px
        let iconZoneRect = NSRect(
            x: trackRect.minX + 1,
            y: trackY + 1,
            width: iconZoneSize,
            height: iconZoneSize
        )
        
        // Position du thumb - peut aller jusqu'au bord gauche du track (avec marge de 1px)
        let thumbMinX = trackRect.minX + 1 + thumbSize / 2 // Marge de 1px + rayon du thumb
        let thumbMaxX = trackRect.maxX - 1 - thumbSize / 2 // Marge de 1px + rayon du thumb
        let thumbRange = thumbMaxX - thumbMinX
        let thumbCenterX = thumbMinX + (thumbRange * percentage)
        let thumbY = rect.midY - thumbSize / 2
        
        // TOUJOURS dessiner le fond blanc de la zone d'icône en premier
        let iconZonePath = NSBezierPath(ovalIn: iconZoneRect)
        NSColor.white.setFill()
        iconZonePath.fill()
        
        // Dessiner la barre blanche continue SEULEMENT si percentage > 0
        if percentage > 0 {
            let fillY = trackY + 1
            let fillEndX = thumbCenterX
            
            // La barre commence depuis le centre de la zone d'icône pour éviter le clipping
            let fillStartX = iconZoneRect.midX
            
            // Créer la barre complète du centre de l'icône jusqu'au centre du thumb
            let fillRect = NSRect(
                x: fillStartX,
                y: fillY,
                width: max(0, fillEndX - fillStartX),
                height: fillHeight
            )
            
            if fillRect.width > 0 {
                // Rectangle simple sans arrondi (l'arrondi gauche est géré par la zone d'icône)
                let fillPath = NSBezierPath(rect: fillRect)
                NSColor.white.setFill()
                fillPath.fill()
            }
        }
        
        // Dessiner le thumb circulaire blanc
        let thumbRect = NSRect(x: thumbCenterX - thumbSize / 2, y: thumbY, width: thumbSize, height: thumbSize)
        let thumbPath = NSBezierPath(ovalIn: thumbRect)
        NSColor.white.setFill()
        thumbPath.fill()
        
        // Ajouter un contour subtil au thumb pour plus de définition
        let thumbStroke = NSBezierPath(ovalIn: thumbRect)
        NSColor.black.withAlphaComponent(0.1).setStroke()
        thumbStroke.lineWidth = 0.5
        thumbStroke.stroke()
        
        // Dessiner l'icône volume EN DERNIER (premier plan) - toujours visible
        drawVolumeIcon(in: iconZoneRect)
    }
    
    private func drawVolumeIcon(in rect: NSRect) {
        // Dessiner une icône de volume simple à gauche du fill
        let iconSize: CGFloat = 10
        let iconX = rect.minX + 6
        let iconY = rect.midY - iconSize / 2
        let iconRect = NSRect(x: iconX, y: iconY, width: iconSize, height: iconSize)
        
        NSColor.black.setFill()
        
        // Dessiner l'icône du haut-parleur
        let speakerPath = NSBezierPath()
        speakerPath.move(to: NSPoint(x: iconRect.minX, y: iconRect.minY + 2))
        speakerPath.line(to: NSPoint(x: iconRect.minX + 2, y: iconRect.minY + 2))
        speakerPath.line(to: NSPoint(x: iconRect.minX + 4, y: iconRect.minY))
        speakerPath.line(to: NSPoint(x: iconRect.minX + 4, y: iconRect.maxY))
        speakerPath.line(to: NSPoint(x: iconRect.minX + 2, y: iconRect.maxY - 2))
        speakerPath.line(to: NSPoint(x: iconRect.minX, y: iconRect.maxY - 2))
        speakerPath.close()
        speakerPath.fill()
        
        // Ajouter une onde sonore
        let wave = NSBezierPath()
        wave.move(to: NSPoint(x: iconRect.minX + 6, y: iconRect.minY + 3))
        wave.curve(to: NSPoint(x: iconRect.minX + 6, y: iconRect.maxY - 3),
                   controlPoint1: NSPoint(x: iconRect.minX + 8, y: iconRect.minY + 3),
                   controlPoint2: NSPoint(x: iconRect.minX + 8, y: iconRect.maxY - 3))
        wave.lineWidth = 0.8
        wave.stroke()
    }
    
    override func mouseDown(with event: NSEvent) {
        updateValueFromMouse(event)
    }
    
    override func mouseDragged(with event: NSEvent) {
        updateValueFromMouse(event)
    }
    
    private func updateValueFromMouse(_ event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let trackRect = NSRect(x: 0, y: bounds.midY - trackHeight / 2, width: bounds.width, height: trackHeight)
        
        if trackRect.contains(point) || event.type == .leftMouseDragged {
            // Calculer les limites du thumb - peut aller jusqu'aux bords avec marge de 1px
            let thumbMinX = trackRect.minX + 1 + thumbSize / 2
            let thumbMaxX = trackRect.maxX - 1 - thumbSize / 2
            let thumbRange = thumbMaxX - thumbMinX
            
            let relativeX = max(0, min(thumbRange, point.x - thumbMinX))
            let percentage = thumbRange > 0 ? relativeX / thumbRange : 0
            let newValue = minValue + (maxValue - minValue) * Double(percentage)
            
            doubleValue = max(minValue, min(maxValue, newValue))
            
            // Envoyer l'action
            if let target = target, let action = action {
                NSApp.sendAction(action, to: target, from: self)
            }
            
            needsDisplay = true
        }
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
