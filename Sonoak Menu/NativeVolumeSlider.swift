import AppKit

class NativeVolumeSlider: NSSlider {
    // MARK: - Constants
    private let trackHeight: CGFloat = 22
    private let fillHeight: CGFloat = 20
    private let thumbSize: CGFloat = 20
    private let iconSize: CGFloat = 18
    private let iconX: CGFloat = 2
    private let fixedFillStartX: CGFloat = 11.0
    
    // Transition constants
    private let transitionStart: CGFloat = 32
    private let transitionEnd: CGFloat = 16
    
    // Opacity constants
    private let inactiveWaveOpacity: Float = 0.24
    private let maxStrokeOpacity: Float = 0.12
    private let maxShadowOpacity: Float = 0.1
    private let thumbColorVariation: Double = 0.06
    
    // Wave activation thresholds
    private let wave2Threshold: Double = 0.33
    private let wave3Threshold: Double = 0.66
    
    // MARK: - Properties
    private var thumbLayer: CALayer!
    private var fillLayer: CALayer!
    private var trackLayer: CALayer!
    private var iconLayer: CALayer!
    private var isThumbPressed: Bool = false
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupSlider()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupSlider()
    }
    
    override func awakeFromNib() {
        super.awakeFromNib()
        setupSlider()
    }
    
    private func setupSlider() {
        sliderType = .linear
        isContinuous = true
        controlSize = .regular
        cell = NativeVolumeSliderCell()
        minValue = 0
        maxValue = 100
        wantsLayer = true
        setupAnimationLayers()
        
        if #available(macOS 10.14, *) {
            trackFillColor = NSColor.white
        }
    }
    
    private func setupAnimationLayers() {
        guard let mainLayer = layer else { return }
        
        trackLayer = CALayer()
        trackLayer.cornerRadius = trackHeight / 2
        if #available(macOS 10.14, *) {
            trackLayer.backgroundColor = NSColor.tertiaryLabelColor.cgColor
        } else {
            trackLayer.backgroundColor = NSColor.lightGray.withAlphaComponent(0.2).cgColor
        }
        mainLayer.addSublayer(trackLayer)
        
        iconLayer = CALayer()
        iconLayer.cornerRadius = fillHeight / 2
        iconLayer.backgroundColor = NSColor.white.cgColor
        mainLayer.addSublayer(iconLayer)
        
        fillLayer = CALayer()
        fillLayer.backgroundColor = NSColor.white.cgColor
        fillLayer.actions = [
            "bounds": createSmoothAnimation(),
            "frame": createSmoothAnimation(),
            "position": createSmoothAnimation()
        ]
        mainLayer.addSublayer(fillLayer)
        
        thumbLayer = CALayer()
        thumbLayer.cornerRadius = thumbSize / 2
        thumbLayer.backgroundColor = NSColor.white.cgColor
        thumbLayer.borderWidth = 1.0
        thumbLayer.borderColor = NSColor.black.withAlphaComponent(0.5).cgColor
        
        // AJOUT : Shadow très légère sur le thumb
        thumbLayer.shadowColor = NSColor.black.cgColor
        thumbLayer.shadowOpacity = 0.1        // Opacité très faible (10%)
        thumbLayer.shadowOffset = CGSize(width: 0, height: 1)  // Décalage vers le bas
        thumbLayer.shadowRadius = 2.0        // Rayon de flou
        
        thumbLayer.actions = [
            "position": createSmoothAnimation(),
            "frame": createSmoothAnimation()
        ]
        mainLayer.addSublayer(thumbLayer)
        
        addVolumeIcon()
        updateLayerPositions()
    }
    
    private func createSmoothAnimation() -> CABasicAnimation {
        let animation = CABasicAnimation()
        animation.duration = 0.25
        animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
        return animation
    }
    
    private func addVolumeIcon() {
        guard let mainLayer = layer else { return }
        
        // Couleur grise légèrement plus sombre
        let iconColor = NSColor(white: 0.28, alpha: 1.0).cgColor

        // Base du haut-parleur (toujours visible)
        let speakerLayer = CAShapeLayer()
        speakerLayer.fillColor = iconColor
        
        let speakerPath = CGMutablePath()
        speakerPath.move(to: CGPoint(x: 7.57266, y: 5.11524))
        speakerPath.addCurve(to: CGPoint(x: 7.33008, y: 5.05899),
                            control1: CGPoint(x: 7.49531, y: 5.07657),
                            control2: CGPoint(x: 7.41094, y: 5.05899))
        speakerPath.addCurve(to: CGPoint(x: 6.97852, y: 5.18204),
                            control1: CGPoint(x: 7.20352, y: 5.05899),
                            control2: CGPoint(x: 7.08047, y: 5.10118))
        speakerPath.addLine(to: CGPoint(x: 4.68633, y: 7.03126))
        speakerPath.addLine(to: CGPoint(x: 2.83008, y: 7.03126))
        speakerPath.addCurve(to: CGPoint(x: 2.26758, y: 7.59376),
                            control1: CGPoint(x: 2.5207, y: 7.03126),
                            control2: CGPoint(x: 2.26758, y: 7.28438))
        speakerPath.addLine(to: CGPoint(x: 2.26758, y: 10.4063))
        speakerPath.addCurve(to: CGPoint(x: 2.83008, y: 10.9688),
                            control1: CGPoint(x: 2.26758, y: 10.7156),
                            control2: CGPoint(x: 2.5207, y: 10.9688))
        speakerPath.addLine(to: CGPoint(x: 4.68633, y: 10.9688))
        speakerPath.addLine(to: CGPoint(x: 6.97852, y: 12.8145))
        speakerPath.addCurve(to: CGPoint(x: 7.33008, y: 12.9375),
                            control1: CGPoint(x: 7.08047, y: 12.8953),
                            control2: CGPoint(x: 7.20703, y: 12.9375))
        speakerPath.addCurve(to: CGPoint(x: 7.57266, y: 12.8813),
                            control1: CGPoint(x: 7.41094, y: 12.9375),
                            control2: CGPoint(x: 7.49531, y: 12.9199))
        speakerPath.addCurve(to: CGPoint(x: 7.89258, y: 12.375),
                            control1: CGPoint(x: 7.76953, y: 12.7863),
                            control2: CGPoint(x: 7.89258, y: 12.5895))
        speakerPath.addLine(to: CGPoint(x: 7.89258, y: 5.62501))
        speakerPath.addCurve(to: CGPoint(x: 7.57266, y: 5.11524),
                            control1: CGPoint(x: 7.89258, y: 5.40704),
                            control2: CGPoint(x: 7.76953, y: 5.21016))
        speakerPath.closeSubpath()
        
        speakerLayer.path = speakerPath
        mainLayer.addSublayer(speakerLayer)
        
        // Onde 1 (la plus proche - première à s'activer)
        let wave1Layer = CAShapeLayer()
        wave1Layer.fillColor = iconColor
        wave1Layer.opacity = inactiveWaveOpacity
        
        let wave1Path = CGMutablePath()
        wave1Path.move(to: CGPoint(x: 10.1074, y: 6.416))
        wave1Path.addCurve(to: CGPoint(x: 9.50973, y: 6.41248),
                          control1: CGPoint(x: 9.94215, y: 6.25076),
                          control2: CGPoint(x: 9.67497, y: 6.24725))
        wave1Path.addCurve(to: CGPoint(x: 9.50622, y: 7.01014),
                          control1: CGPoint(x: 9.3445, y: 6.57771),
                          control2: CGPoint(x: 9.34098, y: 6.8449))
        wave1Path.addCurve(to: CGPoint(x: 10.3148, y: 8.99998),
                          control1: CGPoint(x: 10.0265, y: 7.53748),
                          control2: CGPoint(x: 10.3148, y: 8.24412))
        wave1Path.addCurve(to: CGPoint(x: 9.50622, y: 10.9898),
                          control1: CGPoint(x: 10.3148, y: 9.75232),
                          control2: CGPoint(x: 10.0265, y: 10.459))
        wave1Path.addCurve(to: CGPoint(x: 9.50973, y: 11.5875),
                          control1: CGPoint(x: 9.34098, y: 11.1551),
                          control2: CGPoint(x: 9.3445, y: 11.4222))
        wave1Path.addCurve(to: CGPoint(x: 9.80504, y: 11.7105),
                          control1: CGPoint(x: 9.59059, y: 11.6683),
                          control2: CGPoint(x: 9.69957, y: 11.7105))
        wave1Path.addCurve(to: CGPoint(x: 10.1039, y: 11.584),
                          control1: CGPoint(x: 9.91403, y: 11.7105),
                          control2: CGPoint(x: 10.023, y: 11.6683))
        wave1Path.addCurve(to: CGPoint(x: 11.155, y: 9.0035),
                          control1: CGPoint(x: 10.7824, y: 10.8949),
                          control2: CGPoint(x: 11.155, y: 9.98084))
        wave1Path.addCurve(to: CGPoint(x: 10.1074, y: 6.416),
                          control1: CGPoint(x: 11.1586, y: 8.02264),
                          control2: CGPoint(x: 10.7859, y: 7.10506))
        wave1Path.closeSubpath()
        
        wave1Layer.path = wave1Path
        mainLayer.addSublayer(wave1Layer)
        
        // Onde 2 (intermédiaire)
        let wave2Layer = CAShapeLayer()
        wave2Layer.fillColor = iconColor
        wave2Layer.opacity = inactiveWaveOpacity
        
        let wave2Path = CGMutablePath()
        wave2Path.move(to: CGPoint(x: 13.5316, y: 9.00002))
        wave2Path.addCurve(to: CGPoint(x: 11.8863, y: 4.96057),
                          control1: CGPoint(x: 13.5316, y: 7.47072),
                          control2: CGPoint(x: 12.948, y: 6.03635))
        wave2Path.addCurve(to: CGPoint(x: 11.2887, y: 4.95705),
                          control1: CGPoint(x: 11.7211, y: 4.79533),
                          control2: CGPoint(x: 11.4539, y: 4.79182))
        wave2Path.addCurve(to: CGPoint(x: 11.2851, y: 5.55471),
                          control1: CGPoint(x: 11.1234, y: 5.12229),
                          control2: CGPoint(x: 11.1199, y: 5.38947))
        wave2Path.addCurve(to: CGPoint(x: 12.6879, y: 9.00354),
                          control1: CGPoint(x: 12.1887, y: 6.47229),
                          control2: CGPoint(x: 12.6879, y: 7.69572))
        wave2Path.addCurve(to: CGPoint(x: 11.2851, y: 12.4524),
                          control1: CGPoint(x: 12.6879, y: 10.3113),
                          control2: CGPoint(x: 12.1887, y: 11.5348))
        wave2Path.addCurve(to: CGPoint(x: 11.2887, y: 13.05),
                          control1: CGPoint(x: 11.1199, y: 12.6176),
                          control2: CGPoint(x: 11.1234, y: 12.8848))
        wave2Path.addCurve(to: CGPoint(x: 11.584, y: 13.1731),
                          control1: CGPoint(x: 11.3695, y: 13.1309),
                          control2: CGPoint(x: 11.4785, y: 13.1731))
        wave2Path.addCurve(to: CGPoint(x: 11.8828, y: 13.0465),
                          control1: CGPoint(x: 11.693, y: 13.1731),
                          control2: CGPoint(x: 11.8019, y: 13.1309))
        wave2Path.addCurve(to: CGPoint(x: 13.5316, y: 9.00002),
                          control1: CGPoint(x: 12.9445, y: 11.9637),
                          control2: CGPoint(x: 13.5316, y: 10.5293))
        wave2Path.closeSubpath()
        
        wave2Layer.path = wave2Path
        mainLayer.addSublayer(wave2Layer)
        
        // Onde 3 (la plus éloignée - dernière à s'activer)
        let wave3Layer = CAShapeLayer()
        wave3Layer.fillColor = iconColor
        wave3Layer.opacity = inactiveWaveOpacity
        
        let wave3Path = CGMutablePath()
        wave3Path.move(to: CGPoint(x: 13.4332, y: 3.49807))
        wave3Path.addCurve(to: CGPoint(x: 15.7324, y: 9.00002),
                          control1: CGPoint(x: 14.9168, y: 4.96408),
                          control2: CGPoint(x: 15.7324, y: 6.91525))
        wave3Path.addCurve(to: CGPoint(x: 13.4297, y: 14.502),
                          control1: CGPoint(x: 15.7324, y: 11.0848),
                          control2: CGPoint(x: 14.9168, y: 13.0395))
        wave3Path.addCurve(to: CGPoint(x: 13.1344, y: 14.625),
                          control1: CGPoint(x: 13.3488, y: 14.5828),
                          control2: CGPoint(x: 13.2399, y: 14.625))
        wave3Path.addCurve(to: CGPoint(x: 12.8356, y: 14.4985),
                          control1: CGPoint(x: 13.0254, y: 14.625),
                          control2: CGPoint(x: 12.9164, y: 14.5828))
        wave3Path.addCurve(to: CGPoint(x: 12.8391, y: 13.9008),
                          control1: CGPoint(x: 12.6703, y: 14.3332),
                          control2: CGPoint(x: 12.6738, y: 14.066))
        wave3Path.addCurve(to: CGPoint(x: 14.8852, y: 9.00002),
                          control1: CGPoint(x: 14.1574, y: 12.5965),
                          control2: CGPoint(x: 14.8852, y: 10.8563))
        wave3Path.addCurve(to: CGPoint(x: 12.8391, y: 4.09924),
                          control1: CGPoint(x: 14.8852, y: 7.14377),
                          control2: CGPoint(x: 14.161, y: 5.40354))
        wave3Path.addCurve(to: CGPoint(x: 12.8356, y: 3.50158),
                          control1: CGPoint(x: 12.6738, y: 3.934),
                          control2: CGPoint(x: 12.6703, y: 3.66682))
        wave3Path.addCurve(to: CGPoint(x: 13.4332, y: 3.49807),
                          control1: CGPoint(x: 13.0008, y: 3.33635),
                          control2: CGPoint(x: 13.268, y: 3.33283))
        wave3Path.closeSubpath()
        
        wave3Layer.path = wave3Path
        mainLayer.addSublayer(wave3Layer)
        
        // Croix de mute (initialement cachée)
        let muteLayer = CAShapeLayer()
        muteLayer.fillColor = iconColor
        muteLayer.opacity = 0.0
        
        let mutePath = CGMutablePath()
        mutePath.move(to: CGPoint(x: 13.7667, y: 6.64366))
        mutePath.addCurve(to: CGPoint(x: 14.3008, y: 6.69737),
                         control1: CGPoint(x: 13.9316, y: 6.53487),
                         control2: CGPoint(x: 14.1557, y: 6.55222))
        mutePath.addCurve(to: CGPoint(x: 14.3546, y: 7.23155),
                         control1: CGPoint(x: 14.446, y: 6.84255),
                         control2: CGPoint(x: 14.4633, y: 7.0666))
        mutePath.addLine(to: CGPoint(x: 14.3008, y: 7.29893))
        mutePath.addLine(to: CGPoint(x: 12.6016, y: 8.99815))
        mutePath.addLine(to: CGPoint(x: 14.3008, y: 10.6974))
        mutePath.addLine(to: CGPoint(x: 14.3546, y: 10.7648))
        mutePath.addCurve(to: CGPoint(x: 14.3008, y: 11.2989),
                         control1: CGPoint(x: 14.4634, y: 10.9297),
                         control2: CGPoint(x: 14.446, y: 11.1537))
        mutePath.addCurve(to: CGPoint(x: 13.7667, y: 11.3526),
                         control1: CGPoint(x: 14.1556, y: 11.4441),
                         control2: CGPoint(x: 13.9316, y: 11.4615))
        mutePath.addLine(to: CGPoint(x: 13.6993, y: 11.2989))
        mutePath.addLine(to: CGPoint(x: 12.0001, y: 9.59972))
        mutePath.addLine(to: CGPoint(x: 10.3008, y: 11.2989))
        mutePath.addLine(to: CGPoint(x: 10.2335, y: 11.3526))
        mutePath.addCurve(to: CGPoint(x: 9.69928, y: 11.2989),
                         control1: CGPoint(x: 10.0685, y: 11.4615),
                         control2: CGPoint(x: 9.84448, y: 11.4441))
        mutePath.addCurve(to: CGPoint(x: 9.64557, y: 10.7648),
                         control1: CGPoint(x: 9.5541, y: 11.1537),
                         control2: CGPoint(x: 9.53672, y: 10.9297))
        mutePath.addLine(to: CGPoint(x: 9.69928, y: 10.6974))
        mutePath.addLine(to: CGPoint(x: 11.3985, y: 8.99815))
        mutePath.addLine(to: CGPoint(x: 9.69928, y: 7.29893))
        mutePath.addLine(to: CGPoint(x: 9.64557, y: 7.23155))
        mutePath.addCurve(to: CGPoint(x: 9.69928, y: 6.69737),
                         control1: CGPoint(x: 9.53674, y: 7.0666),
                         control2: CGPoint(x: 9.55409, y: 6.84256))
        mutePath.addCurve(to: CGPoint(x: 10.2335, y: 6.64366),
                         control1: CGPoint(x: 9.84448, y: 6.55224),
                         control2: CGPoint(x: 10.0685, y: 6.53483))
        mutePath.addLine(to: CGPoint(x: 10.3008, y: 6.69737))
        mutePath.addLine(to: CGPoint(x: 12.0001, y: 8.39659))
        mutePath.addLine(to: CGPoint(x: 13.6993, y: 6.69737))
        mutePath.addLine(to: CGPoint(x: 13.7667, y: 6.64366))
        mutePath.closeSubpath()
        
        muteLayer.path = mutePath
        mainLayer.addSublayer(muteLayer)
        
        // Stocker les références pour les animations
        speakerLayer.name = "speaker"
        wave1Layer.name = "wave1"
        wave2Layer.name = "wave2"
        wave3Layer.name = "wave3"
        muteLayer.name = "mute"
        
        updateVolumeIconPosition(speakerLayer)
        updateVolumeIconPosition(wave1Layer)
        updateVolumeIconPosition(wave2Layer)
        updateVolumeIconPosition(wave3Layer)
        updateVolumeIconPosition(muteLayer)
    }
    
    private func updateVolumeIconPosition(_ iconLayer: CALayer) {
        let trackY = bounds.midY - trackHeight / 2
        let iconY = trackY + 1 + (fillHeight - iconSize) / 2
        
        iconLayer.frame = NSRect(x: iconX, y: iconY, width: iconSize, height: iconSize)
    }
    
    override func layout() {
        super.layout()
        updateLayerPositions()
        updateVolumeIconPositions()
    }
    
    override func draw(_ dirtyRect: NSRect) {
        // Les CALayers gèrent tout l'affichage
    }
    
    private func updateLayerPositions() {
        guard layer != nil else { return }
        
        let trackY = bounds.midY - trackHeight / 2
        let percentage = CGFloat((doubleValue - minValue) / (maxValue - minValue))
        
        trackLayer.frame = NSRect(x: 0, y: trackY, width: bounds.width, height: trackHeight)
        
        // Garder la position originale du cercle d'icône (ne pas la changer)
        let iconZoneRect = NSRect(x: 1, y: trackY + 1, width: fillHeight, height: fillHeight)
        iconLayer.frame = iconZoneRect
        
        let thumbRange = bounds.width - 2 - thumbSize
        let thumbX = 1 + (thumbRange * percentage)
        let thumbY = bounds.midY - thumbSize / 2
        thumbLayer.frame = NSRect(x: thumbX, y: thumbY, width: thumbSize, height: thumbSize)
        
        if percentage > 0 {
            let thumbCenterX = thumbX + thumbSize / 2
            let fillWidth = max(0, thumbCenterX - fixedFillStartX)
            fillLayer.frame = NSRect(x: fixedFillStartX, y: trackY + 1, width: fillWidth, height: fillHeight)
            
            print("🎯 Volume: \(Int(percentage * 100))% - FillStart: \(fixedFillStartX), Width: \(fillWidth)")
        } else {
            fillLayer.frame = NSRect(x: fixedFillStartX, y: trackY + 1, width: 0, height: fillHeight)
            print("🎯 Volume: 0% - Fill masqué")
        }
        
        // Gestion de l'opacité du stroke du thumb
        updateThumbStrokeOpacity(thumbX: thumbX, iconZoneRect: iconZoneRect)
        
        // IMPORTANT : Mettre à jour les ondes à chaque changement de position !
        updateWaveOpacities()
    }
    
    private func updateThumbStrokeOpacity(thumbX: CGFloat, iconZoneRect: NSRect) {
        // Distance depuis le début du slider (bord GAUCHE du thumb, pas le centre)
        let thumbLeftEdge = thumbX
        let distanceFromLeft = thumbLeftEdge
        
        // CORRECTION : Utiliser les mêmes seuils pour stroke ET couleur ET shadow
        let transitionStart: CGFloat = 32    // Transition commence à 32px
        let transitionEnd: CGFloat = 16      // Transition finit à 16px
        
        // Calculer le progress pour les trois propriétés (stroke, couleur, shadow)
        let progress: CGFloat
        if distanceFromLeft >= transitionStart {
            progress = 1.0 // Complètement "loin" du début
        } else if distanceFromLeft <= transitionEnd {
            progress = 0.0 // Complètement "proche" du début
        } else {
            // Transition progressive entre 16px et 32px
            progress = (distanceFromLeft - transitionEnd) / (transitionStart - transitionEnd)
        }
        
        // Calculer l'opacité du stroke avec le même progress
        let strokeOpacity = Float(progress * 0.12)
        
        // Calculer l'opacité de la shadow avec le même progress
        let shadowOpacity = Float(progress * 0.1) // De 0.0 à 0.1
        
        // Calculer la couleur du background avec le même progress
        let dragColor: NSColor
        if isThumbPressed {
            // Interpolation entre blanc (progress=0.0) et gris clair (progress=1.0)
            let grayValue = 1.0 - (progress * 0.06)
            dragColor = NSColor(white: grayValue, alpha: 1.0)
        } else {
            dragColor = NSColor.white // Pas utilisé, mais pour clarté
        }
        
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.1)
        
        if isThumbPressed {
            // Pendant le drag : couleur, stroke ET shadow avec le même progress
            thumbLayer.backgroundColor = dragColor.cgColor
            thumbLayer.borderColor = NSColor.black.withAlphaComponent(CGFloat(strokeOpacity)).cgColor
            thumbLayer.shadowOpacity = shadowOpacity
            print("🖱️ Drag - \(Int(distanceFromLeft))px, progress: \(String(format: "%.2f", progress)), stroke: \(strokeOpacity), shadow: \(shadowOpacity)")
        } else if distanceFromLeft <= transitionEnd {
            // Thumb au début : blanc pur, pas de stroke, pas de shadow
            thumbLayer.backgroundColor = NSColor.white.cgColor
            thumbLayer.borderColor = NSColor.black.withAlphaComponent(0.0).cgColor
            thumbLayer.shadowOpacity = 0.0
            print("📍 Début slider - blanc pur sans stroke ni shadow")
        } else {
            // Thumb normal : blanc avec stroke et shadow selon la distance
            thumbLayer.backgroundColor = NSColor.white.cgColor
            thumbLayer.borderColor = NSColor.black.withAlphaComponent(CGFloat(strokeOpacity)).cgColor
            thumbLayer.shadowOpacity = shadowOpacity
            print("✋ Thumb normal - \(Int(distanceFromLeft))px, stroke: \(strokeOpacity), shadow: \(shadowOpacity)")
        }
        
        CATransaction.commit()
    }
    
    private func updateVolumeIconPositions() {
        guard let mainLayer = layer else { return }
        
        for sublayer in mainLayer.sublayers ?? [] {
            if let name = sublayer.name,
               ["speaker", "wave1", "wave2", "wave3", "mute"].contains(name) {
                updateVolumeIconPosition(sublayer)
            }
        }
        
        // Mettre à jour les opacités des ondes selon le volume
        updateWaveOpacities()
    }
    
    private func updateWaveOpacities() {
        guard let mainLayer = layer else { return }
        
        let volumePercentage = (doubleValue - minValue) / (maxValue - minValue)
        
        let isMuted = volumePercentage == 0
        let wave1Active = volumePercentage > 0
        let wave2Active = volumePercentage > wave2Threshold
        let wave3Active = volumePercentage > wave3Threshold
        
        for sublayer in mainLayer.sublayers ?? [] {
            guard let name = sublayer.name else { continue }
            
            CATransaction.begin()
            CATransaction.setAnimationDuration(0.2)
            CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeInEaseOut))
            
            switch name {
            case "mute":
                sublayer.opacity = isMuted ? 1.0 : 0.0
                
            case "wave1":
                sublayer.opacity = isMuted ? 0.0 : (wave1Active ? 1.0 : inactiveWaveOpacity)
                
            case "wave2":
                sublayer.opacity = isMuted ? 0.0 : (wave2Active ? 1.0 : inactiveWaveOpacity)
                
            case "wave3":
                sublayer.opacity = isMuted ? 0.0 : (wave3Active ? 1.0 : inactiveWaveOpacity)
                
            default:
                break
            }
            
            CATransaction.commit()
        }
    }
    
    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let trackRect = NSRect(x: 0, y: bounds.midY - trackHeight / 2, width: bounds.width, height: trackHeight)
        
        guard trackRect.contains(point) else { return }
        
        isThumbPressed = true
        
        let thumbMinX = 1 + thumbSize / 2
        let thumbMaxX = bounds.width - 1 - thumbSize / 2
        let thumbRange = thumbMaxX - thumbMinX
        
        let relativeX = max(0, min(thumbRange, point.x - thumbMinX))
        let percentage = thumbRange > 0 ? relativeX / thumbRange : 0
        let newValue = minValue + (maxValue - minValue) * Double(percentage)
        let finalValue = max(minValue, min(maxValue, newValue))
        
        doubleValue = finalValue
        updateLayerPositions()
        
        if let target = target, let action = action {
            NSApp.sendAction(action, to: target, from: self)
        }
    }
    
    override func mouseUp(with event: NSEvent) {
        isThumbPressed = false
        updateLayerPositions()
    }
    
    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        
        let thumbMinX = 1 + thumbSize / 2
        let thumbMaxX = bounds.width - 1 - thumbSize / 2
        let thumbRange = thumbMaxX - thumbMinX
        
        let relativeX = max(0, min(thumbRange, point.x - thumbMinX))
        let percentage = thumbRange > 0 ? relativeX / thumbRange : 0
        let newValue = minValue + (maxValue - minValue) * Double(percentage)
        let finalValue = max(minValue, min(maxValue, newValue))
        
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        doubleValue = finalValue
        updateLayerPositions()
        CATransaction.commit()
        
        if let target = target, let action = action {
            NSApp.sendAction(action, to: target, from: self)
        }
    }
}

class NativeVolumeSliderCell: NSSliderCell {
    override func drawBar(inside rect: NSRect, flipped: Bool) {}
    override func drawKnob(_ knobRect: NSRect) {}
}
