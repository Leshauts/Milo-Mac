import Foundation
import Network

protocol WebSocketServiceDelegate: AnyObject {
    func didReceiveStateUpdate(_ state: OakOSState)
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
    private let maxReconnectAttempts = 5
    private var reconnectTimer: Timer?
    
    private var host: String?
    private var port: Int = 8000
    
    override init() {
        super.init()
        setupURLSession()
    }
    
    private func setupURLSession() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 30
        urlSession = URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }
    
    func connect(to host: String, port: Int = 8000) {
        self.host = host
        self.port = port
        self.shouldReconnect = true
        self.reconnectAttempts = 0
        
        performConnection()
    }
    
    private func performConnection() {
        guard let host = host else { return }
        
        let urlString = "ws://\(host):\(port)/ws"
        guard let url = URL(string: urlString) else {
            print("❌ Invalid WebSocket URL: \(urlString)")
            return
        }
        
        print("🔌 Connecting to WebSocket: \(urlString)")
        
        webSocketTask = urlSession?.webSocketTask(with: url)
        webSocketTask?.resume()
        
        startListening()
    }
    
    private func startListening() {
        webSocketTask?.receive { [weak self] result in
            switch result {
            case .success(let message):
                self?.handleMessage(message)
                // Continue listening
                self?.startListening()
                
            case .failure(let error):
                print("❌ WebSocket receive error: \(error)")
                self?.handleDisconnection()
            }
        }
    }
    
    private func handleMessage(_ message: URLSessionWebSocketTask.Message) {
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
        
        print("📡 WebSocket message: \(json)")
        
        // Parser les messages oakOS WebSocket
        if let category = json["category"] as? String,
           let eventType = json["type"] as? String,
           let eventData = json["data"] as? [String: Any] {
            
            handleOakOSEvent(category: category, type: eventType, data: eventData)
        }
    }
    
    private func handleOakOSEvent(category: String, type: String, data: [String: Any]) {
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
        // Extraire l'état complet depuis full_state
        guard let fullState = data["full_state"] as? [String: Any] else { return }
        
        let state = OakOSState(
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
    
    func disconnect() {
        shouldReconnect = false
        reconnectTimer?.invalidate()
        reconnectTimer = nil
        
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        
        if isConnected {
            isConnected = false
            delegate?.webSocketDidDisconnect()
        }
    }
    
    private func handleDisconnection() {
        if isConnected {
            isConnected = false
            DispatchQueue.main.async { [weak self] in
                self?.delegate?.webSocketDidDisconnect()
            }
        }
        
        webSocketTask = nil
        
        // Reconnexion automatique si nécessaire
        if shouldReconnect && reconnectAttempts < maxReconnectAttempts {
            scheduleReconnection()
        }
    }
    
    private func scheduleReconnection() {
        reconnectAttempts += 1
        let delay = min(pow(2.0, Double(reconnectAttempts)), 30.0) // Backoff exponentiel, max 30s
        
        print("🔄 Reconnecting in \(delay) seconds (attempt \(reconnectAttempts)/\(maxReconnectAttempts))")
        
        reconnectTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            self?.performConnection()
        }
    }
    
    deinit {
        disconnect()
    }
}

// MARK: - URLSessionWebSocketDelegate
extension WebSocketService: URLSessionWebSocketDelegate {
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        print("✅ WebSocket connected")
        isConnected = true
        reconnectAttempts = 0
        
        DispatchQueue.main.async { [weak self] in
            self?.delegate?.webSocketDidConnect()
        }
    }
    
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        print("🔌 WebSocket disconnected with code: \(closeCode)")
        handleDisconnection()
    }
}
