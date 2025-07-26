import Foundation
import Network

protocol WebSocketServiceDelegate: AnyObject {
    func didReceiveStateUpdate(_ state: MiloState)
    func didReceiveVolumeUpdate(_ volume: VolumeStatus)
    func webSocketDidConnect()
    func webSocketDidDisconnect()
}

class WebSocketService: NSObject {
    weak var delegate: WebSocketServiceDelegate?
    
    private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    private var isConnected = false
    private var shouldReconnect = true
    private var reconnectAttempts = 0
    private let maxReconnectAttempts = 10  // Augmenté
    private var reconnectTimer: Timer?
    
    private var host: String?
    private var port: Int = 80
    
    // Ping/Pong amélioré
    private var pingTimer: Timer?
    private var lastPongReceived = Date()
    private let pingInterval: TimeInterval = 15.0      // Plus fréquent
    private let pongTimeout: TimeInterval = 8.0        // Plus strict
    private let initialConnectionTimeout: TimeInterval = 10.0
    
    // NOUVEAU : Détection de connexion morte
    private var connectionDeadTimer: Timer?
    private var lastMessageReceived = Date()
    private let maxSilentPeriod: TimeInterval = 45.0   // 45s sans message = connexion morte
    
    override init() {
        super.init()
        setupURLSession()
    }
    
    private func setupURLSession() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = initialConnectionTimeout
        config.timeoutIntervalForResource = 60
        urlSession = URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }
    
    func connect(to host: String, port: Int = 80) {
        NSLog("🔌 WebSocket connecting to \(host):\(port)")
        self.host = host
        self.port = port
        self.shouldReconnect = true
        self.reconnectAttempts = 0
        
        performConnection()
    }
    
    private func performConnection() {
        guard let host = host else { return }
        
        // CORRECTION : Utiliser le bon port pour WebSocket (8000 pour WS, 80 pour API)
        let wsPort = 8000  // WebSocket sur port 8000
        let urlString = "ws://\(host):\(wsPort)/ws"
        
        guard let url = URL(string: urlString) else {
            NSLog("❌ Invalid WebSocket URL: \(urlString)")
            scheduleReconnection()
            return
        }
        
        NSLog("🔌 Connecting to WebSocket: \(urlString)")
        
        // Nettoyer l'ancienne connexion
        webSocketTask?.cancel()
        webSocketTask = nil
        
        webSocketTask = urlSession?.webSocketTask(with: url)
        webSocketTask?.resume()
        
        // Reset des timestamps
        lastPongReceived = Date()
        lastMessageReceived = Date()
        
        startListening()
        startConnectionDeadTimer()
    }
    
    private func startListening() {
        webSocketTask?.receive { [weak self] result in
            switch result {
            case .success(let message):
                self?.handleMessage(message)
                // Continue listening
                self?.startListening()
                
            case .failure(let error):
                NSLog("❌ WebSocket receive error: \(error)")
                // CORRECTION : Détection immédiate de la déconnexion
                DispatchQueue.main.async {
                    self?.handleDisconnection()
                }
            }
        }
    }
    
    private func handleMessage(_ message: URLSessionWebSocketTask.Message) {
        // IMPORTANT : Mettre à jour les timestamps de réception
        lastPongReceived = Date()
        lastMessageReceived = Date()
        
        switch message {
        case .string(let text):
            parseMessage(text)
        case .data(let data):
            if let text = String(data: data, encoding: .utf8) {
                parseMessage(text)
            }
        @unknown default:
            break
        }
    }
    
    private func parseMessage(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }
        
        NSLog("📡 WebSocket message: \(json)")
        
        // Parser les messages Milo WebSocket
        if let category = json["category"] as? String,
           let eventType = json["type"] as? String,
           let eventData = json["data"] as? [String: Any] {
            
            handleMiloEvent(category: category, type: eventType, data: eventData)
        }
    }
    
    private func handleMiloEvent(category: String, type: String, data: [String: Any]) {
        DispatchQueue.main.async { [weak self] in
            switch category {
            case "system":
                if type == "state_changed" || type == "transition_complete" || type == "transition_start" {
                    self?.handleSystemStateChange(data)
                }
                
            case "volume":
                if type == "volume_changed" {
                    self?.handleVolumeChange(data)
                }
                
            case "plugin":
                if type == "state_changed" {
                    self?.handleSystemStateChange(data)
                }
                
            default:
                break
            }
        }
    }
    
    private func handleSystemStateChange(_ data: [String: Any]) {
        guard let fullState = data["full_state"] as? [String: Any] else { return }
        
        let state = MiloState(
            activeSource: fullState["active_source"] as? String ?? "none",
            pluginState: fullState["plugin_state"] as? String ?? "inactive",
            isTransitioning: fullState["transitioning"] as? Bool ?? false,
            multiroomEnabled: fullState["multiroom_enabled"] as? Bool ?? false,
            equalizerEnabled: fullState["equalizer_enabled"] as? Bool ?? false,
            metadata: fullState["metadata"] as? [String: Any] ?? [:]
        )
        
        delegate?.didReceiveStateUpdate(state)
    }
    
    private func handleVolumeChange(_ data: [String: Any]) {
        let volume = data["volume"] as? Int ?? 0
        let mode = data["mode"] as? String ?? "unknown"
        let multiroomEnabled = data["multiroom_enabled"] as? Bool ?? false
        
        let volumeStatus = VolumeStatus(
            volume: volume,
            mode: mode,
            multiroomEnabled: multiroomEnabled
        )
        
        delegate?.didReceiveVolumeUpdate(volumeStatus)
    }
    
    // NOUVEAU : Timer pour détecter les connexions silencieuses
    private func startConnectionDeadTimer() {
        stopConnectionDeadTimer()
        
        connectionDeadTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
            self?.checkConnectionAliveness()
        }
    }
    
    private func stopConnectionDeadTimer() {
        connectionDeadTimer?.invalidate()
        connectionDeadTimer = nil
    }
    
    private func checkConnectionAliveness() {
        let now = Date()
        let timeSinceLastMessage = now.timeIntervalSince(lastMessageReceived)
        
        if timeSinceLastMessage > maxSilentPeriod {
            NSLog("💀 Connection appears dead (no messages for \(Int(timeSinceLastMessage))s)")
            handleDisconnection()
        }
    }
    
    private func startPingTimer() {
        stopPingTimer()
        
        pingTimer = Timer.scheduledTimer(withTimeInterval: pingInterval, repeats: true) { [weak self] _ in
            self?.sendPing()
        }
    }
    
    private func stopPingTimer() {
        pingTimer?.invalidate()
        pingTimer = nil
    }
    
    private func sendPing() {
        guard let webSocketTask = webSocketTask else {
            handleDisconnection()
            return
        }
        
        NSLog("🏓 Sending ping...")
        
        webSocketTask.sendPing { [weak self] error in
            if let error = error {
                NSLog("❌ Ping failed: \(error)")
                self?.handleDisconnection()
            } else {
                // Vérifier si on a reçu des données récemment
                let now = Date()
                if let lastMessage = self?.lastMessageReceived,
                   now.timeIntervalSince(lastMessage) > self?.pongTimeout ?? 8.0 {
                    NSLog("💔 Pong timeout - connexion considérée morte")
                    self?.handleDisconnection()
                }
            }
        }
    }
    
    func disconnect() {
        NSLog("🔌 WebSocket disconnecting...")
        shouldReconnect = false
        
        stopAllTimers()
        
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        
        if isConnected {
            isConnected = false
            delegate?.webSocketDidDisconnect()
        }
    }
    
    private func handleDisconnection() {
        NSLog("💔 WebSocket handling disconnection...")
        
        stopAllTimers()
        
        if isConnected {
            isConnected = false
            // CORRECTION : Notification immédiate sur le main thread
            DispatchQueue.main.async { [weak self] in
                self?.delegate?.webSocketDidDisconnect()
            }
        }
        
        webSocketTask?.cancel()
        webSocketTask = nil
        
        // Reconnexion automatique si nécessaire
        if shouldReconnect && reconnectAttempts < maxReconnectAttempts {
            scheduleReconnection()
        } else if reconnectAttempts >= maxReconnectAttempts {
            NSLog("❌ Max reconnection attempts reached")
        }
    }
    
    private func scheduleReconnection() {
        reconnectAttempts += 1
        let delay = min(pow(2.0, Double(reconnectAttempts)), 30.0) // Backoff exponentiel, max 30s
        
        NSLog("🔄 WebSocket reconnecting in \(Int(delay)) seconds (attempt \(reconnectAttempts)/\(maxReconnectAttempts))")
        
        reconnectTimer?.invalidate()
        reconnectTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            self?.performConnection()
        }
    }
    
    private func stopAllTimers() {
        stopPingTimer()
        stopConnectionDeadTimer()
        reconnectTimer?.invalidate()
        reconnectTimer = nil
    }
    
    // NOUVEAU : Méthode pour forcer la reconnexion depuis l'extérieur
    func forceReconnect() {
        NSLog("🔄 Force WebSocket reconnection requested")
        
        // CORRECTION : Ne pas réinitialiser reconnectAttempts pour éviter les boucles
        if !isConnected {
            performConnection()
        }
    }
    
    // NOUVEAU : État de connexion
    func getConnectionState() -> Bool {
        return isConnected
    }
    
    deinit {
        stopAllTimers()
        disconnect()
    }
}

// MARK: - URLSessionWebSocketDelegate
extension WebSocketService: URLSessionWebSocketDelegate {
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        NSLog("✅ WebSocket connected")
        isConnected = true
        reconnectAttempts = 0
        
        // Reset des timestamps
        lastPongReceived = Date()
        lastMessageReceived = Date()
        
        // Démarrer les timers de surveillance
        startPingTimer()
        startConnectionDeadTimer()
        
        DispatchQueue.main.async { [weak self] in
            self?.delegate?.webSocketDidConnect()
        }
    }
    
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        let reasonString = reason.flatMap { String(data: $0, encoding: .utf8) } ?? "No reason"
        NSLog("🔌 WebSocket disconnected with code: \(closeCode), reason: \(reasonString)")
        handleDisconnection()
    }
}
