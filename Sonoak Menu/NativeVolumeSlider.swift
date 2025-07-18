import AppKit

class NativeVolumeSlider: NSSlider {
    private let trackHeight: CGFloat = 22
    private let fillHeight: CGFloat = 20
    private let thumbSize: CGFloat = 20
    
    private var thumbLayer: CALayer!
    private var fillLayer: CALayer!
    private var trackLayer: CALayer!
    private var iconLayer: CALayer!
    private var isThumbPressed: Bool = false
    private var thumbPressedColor: NSColor = NSColor.lightGray
    
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
            "frame": createSmoothAnimation()
        ]
        mainLayer.addSublayer(fillLayer)
        
        thumbLayer = CALayer()
        thumbLayer.cornerRadius = thumbSize / 2
        thumbLayer.backgroundColor = NSColor.white.cgColor
        thumbLayer.borderWidth = 1.0
        thumbLayer.borderColor = NSColor.black.withAlphaComponent(0.5).cgColor
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
        
        let volumeIconLayer = CAShapeLayer()
        volumeIconLayer.fillColor = NSColor.black.cgColor
        volumeIconLayer.strokeColor = NSColor.black.cgColor
        volumeIconLayer.lineWidth = 0.8
        
        let iconPath = CGMutablePath()
        iconPath.move(to: CGPoint(x: 0, y: 2))
        iconPath.addLine(to: CGPoint(x: 2, y: 2))
        iconPath.addLine(to: CGPoint(x: 4, y: 0))
        iconPath.addLine(to: CGPoint(x: 4, y: 10))
        iconPath.addLine(to: CGPoint(x: 2, y: 8))
        iconPath.addLine(to: CGPoint(x: 0, y: 8))
        iconPath.closeSubpath()
        
        let wavePath = CGMutablePath()
        wavePath.move(to: CGPoint(x: 6, y: 3))
        wavePath.addCurve(to: CGPoint(x: 6, y: 7),
                         control1: CGPoint(x: 8, y: 3),
                         control2: CGPoint(x: 8, y: 7))
        iconPath.addPath(wavePath)
        
        volumeIconLayer.path = iconPath
        mainLayer.addSublayer(volumeIconLayer)
        updateVolumeIconPosition(volumeIconLayer)
    }
    
    private func updateVolumeIconPosition(_ volumeIconLayer: CAShapeLayer) {
        let trackY = bounds.midY - trackHeight / 2
        let iconSize: CGFloat = 10
        let iconX: CGFloat = 7
        let iconY = trackY + 1 + (fillHeight - iconSize) / 2
        
        volumeIconLayer.frame = NSRect(x: iconX, y: iconY, width: iconSize, height: iconSize)
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
        
        let iconZoneRect = NSRect(x: 1, y: trackY + 1, width: fillHeight, height: fillHeight)
        iconLayer.frame = iconZoneRect
        
        let thumbRange = bounds.width - 2 - thumbSize
        let thumbX = 1 + (thumbRange * percentage)
        let thumbY = bounds.midY - thumbSize / 2
        thumbLayer.frame = NSRect(x: thumbX, y: thumbY, width: thumbSize, height: thumbSize)
        
        if percentage > 0 {
            let fillStartX = iconZoneRect.midX
            let thumbCenterX = 1 + (bounds.width - 2 - thumbSize) * percentage + thumbSize / 2
            let fillWidth = max(0, thumbCenterX - fillStartX)
            fillLayer.frame = NSRect(x: fillStartX, y: trackY + 1, width: fillWidth, height: fillHeight)
        } else {
            fillLayer.frame = .zero
        }
        
        thumbLayer.backgroundColor = isThumbPressed ? thumbPressedColor.cgColor : NSColor.white.cgColor
    }
    
    private func updateVolumeIconPositions() {
        guard let mainLayer = layer else { return }
        
        for sublayer in mainLayer.sublayers ?? [] {
            if let volumeIconLayer = sublayer as? CAShapeLayer {
                updateVolumeIconPosition(volumeIconLayer)
            }
        }
    }
    
    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let trackRect = NSRect(x: 0, y: bounds.midY - trackHeight / 2, width: bounds.width, height: trackHeight)
        
        guard trackRect.contains(point) else { return }
        
        let thumbMinX = 1 + thumbSize / 2
        let thumbMaxX = bounds.width - 1 - thumbSize / 2
        let thumbRange = thumbMaxX - thumbMinX
        
        let relativeX = max(0, min(thumbRange, point.x - thumbMinX))
        let percentage = thumbRange > 0 ? relativeX / thumbRange : 0
        let newValue = minValue + (maxValue - minValue) * Double(percentage)
        let finalValue = max(minValue, min(maxValue, newValue))
        
        print("🎯 Clic: \(doubleValue) -> \(finalValue)")
        
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
