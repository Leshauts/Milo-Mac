import AppKit

class LoadingSpinner: NSView {
    private let strokeWidth: CGFloat = 1.5
    private let animationDuration: Double = 1.4
    private var animationTimer: Timer?
    private var currentStep = 0
    private let totalSteps = 8  // 8 positions, rotation continue
    
    // Les 8 positions du spinner dans l'ordre horaire (12h en haut)
    private let positions: [CGFloat] = [90, 135, 180, 225, 270, 315, 0, 45]  // 12h, 1h30, 3h, 4h30, 6h, 7h30, 9h, 10h30
    
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
        layer?.backgroundColor = NSColor.clear.cgColor
    }
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        
        // Centrer le spinner en 16x16
        let spinnerSize: CGFloat = 18
        let centerX = bounds.midX
        let centerY = bounds.midY
        let radius: CGFloat = (spinnerSize / 2) - strokeWidth
        
        // Dessiner chaque position avec son opacité
        for (index, angle) in positions.enumerated() {
            let opacity = getOpacityForPosition(index)
            
            // Calculer les points de début et fin du trait
            let startRadius = radius * 0.6
            let endRadius = radius * 0.9
            
            // Convertir l'angle en radians
            let angleRad = angle * .pi / 180
            let startPoint = CGPoint(
                x: centerX + cos(angleRad) * startRadius,
                y: centerY + sin(angleRad) * startRadius
            )
            let endPoint = CGPoint(
                x: centerX + cos(angleRad) * endRadius,
                y: centerY + sin(angleRad) * endRadius
            )
            
            // Configurer la couleur avec l'opacité
            context.setStrokeColor(NSColor.white.withAlphaComponent(opacity).cgColor)
            context.setLineWidth(strokeWidth)
            context.setLineCap(.round)
            
            // Dessiner le trait
            context.move(to: startPoint)
            context.addLine(to: endPoint)
            context.strokePath()
        }
    }
    
    private func getOpacityForPosition(_ position: Int) -> CGFloat {
        // Animation corrigée : la "lumière" avance et laisse une traînée derrière
        // currentStep indique la position "de fin de traînée"
        
        // Calculer la distance entre cette position et la position actuelle
        let distance = (position - currentStep + 8) % 8
        
        switch distance {
        case 0: return 0.16     // Position actuelle (fin de traînée)
        case 1: return 0.32     // 1 position derrière
        case 2: return 0.64     // 2 positions derrière
        case 3: return 1.0      // 3 positions derrière (tête de la lumière - la plus brillante)
        default: return 0.16    // Toutes les autres positions (faibles)
        }
    }
    
    func startAnimating() {
        stopAnimating()
        
        print("🎬 LoadingSpinner: Starting animation")
        
        // Commencer avec currentStep = 5 pour que 12h (maintenant en position index 0) soit case 3 (position la plus brillante)
        // (0 - 5 + 8) % 8 = 3 → case 3 → opacity 1.0 sur 12h (maintenant en haut)
        currentStep = 5
        needsDisplay = true
        
        // Timer : 1.4s / 8 positions = 0.175s par step
        let stepInterval = animationDuration / Double(totalSteps)
        
        animationTimer = Timer.scheduledTimer(withTimeInterval: stepInterval, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            
            // Avancer à la position suivante (sens horaire)
            self.currentStep = (self.currentStep + 1) % self.totalSteps
            
            // Debug : afficher où est la tête de lumière (3 positions avant currentStep)
            let positions = ["12h", "1h30", "3h", "4h30", "6h", "7h30", "9h", "10h30"]
            let lightHeadPos = (self.currentStep + 3) % 8
            let currentPos = positions[lightHeadPos]
            print("🎬 Étape \(self.currentStep): Lumière sur \(currentPos)")
            
            // Redessiner
            DispatchQueue.main.async {
                self.needsDisplay = true
            }
        }
        
        // S'assurer que le timer fonctionne même quand le menu est ouvert
        if let timer = animationTimer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }
    
    func stopAnimating() {
        print("🛑 LoadingSpinner: Stopping animation")
        animationTimer?.invalidate()
        animationTimer = nil
        currentStep = 5  // Même position de départ pour être cohérent
        needsDisplay = true
    }
    
    deinit {
        stopAnimating()
    }
}
