import Foundation
import Network

protocol MiloConnectionManagerDelegate: AnyObject {
    func miloDidConnect()
    func miloDidDisconnect()
    func didReceiveStateUpdate(_ state: MiloState)
    func didReceiveVolumeUpdate(_ volume: VolumeStatus)
}

class MiloConnectionManager: NSObject {
    weak var delegate: MiloConnectionManagerDelegate?
    
    // Configuration
    private let host = "milo.local"
    private let httpPort = 80
    private let wsPort = 8000
    
    // État simple
    private var isConnected = false
    private var shouldConnect = true
    
    // Services
    private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    private var apiService: MiloAPIService?
    
    // mDNS/Bonjour Discovery
    private var serviceBrowser: NetServiceBrowser?
    private var isDiscovering = false
    
    // Retry ciblé (quand mDNS trouve le Pi)
    private var retryTimer: Timer?
    private var retryCount = 0
    private var isRetrying = false  // Protection contre retry multiples
    private let maxRetries = 20
    private let retryInterval: TimeInterval = 2.0
    
    override init() {
        super.init()
        setupURLSession()
    }
    
    private func setupURLSession() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 5.0
        config.timeoutIntervalForResource = 30.0
        urlSession = URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }
    
    // MARK: - Public Interface
    
    func start() {
        NSLog("🎯 MiloConnectionManager starting with mDNS + retry...")
        shouldConnect = true
        startDiscovery()
    }
    
    func stop() {
        NSLog("🛑 MiloConnectionManager stopping...")
        shouldConnect = false
        stopDiscovery()
        stopRetry()
        disconnect()
    }
    
    func getAPIService() -> MiloAPIService? {
        return apiService
    }
    
    func isCurrentlyConnected() -> Bool {
        return isConnected
    }
    
    // MARK: - mDNS Discovery
    
    private func startDiscovery() {
        guard shouldConnect && !isDiscovering else { return }
        
        NSLog("📡 Starting mDNS discovery for milo.local...")
        isDiscovering = true
        
        serviceBrowser = NetServiceBrowser()
        serviceBrowser?.delegate = self
        serviceBrowser?.searchForServices(ofType: "_http._tcp", inDomain: "local.")
    }
    
    private func stopDiscovery() {
        NSLog("🛑 Stopping mDNS discovery")
        isDiscovering = false
        
        serviceBrowser?.stop()
        serviceBrowser?.delegate = nil
        serviceBrowser = nil
    }
    
    // MARK: - Retry ciblé (quand mDNS trouve Milo)
    
    private func startAPIRetry() {
        // Protection contre retry multiples
        guard !isRetrying && !isConnected else { return }
        
        NSLog("🔄 Milo detected - starting 20 rapid API tests...")
        
        // Arrêter mDNS pendant les retry
        stopDiscovery()
        
        isRetrying = true
        retryCount = 0
        testAPIWithRetry()
        
        // Programmer les retry suivants
        retryTimer = Timer.scheduledTimer(withTimeInterval: retryInterval, repeats: true) { [weak self] _ in
            self?.testAPIWithRetry()
        }
    }
    
    private func stopRetry() {
        retryTimer?.invalidate()
        retryTimer = nil
        retryCount = 0
        isRetrying = false
    }
    
    private func testAPIWithRetry() {
        retryCount += 1
        NSLog("🔍 API test \(retryCount)/\(maxRetries)...")
        
        Task {
            do {
                let testAPI = MiloAPIService(host: host, port: httpPort)
                _ = try await testAPI.fetchState()
                
                NSLog("✅ API ready after \(retryCount) attempts!")
                await connectToMilo()
                
            } catch {
                NSLog("❌ API test \(retryCount) failed: \(error.localizedDescription)")
                
                if retryCount >= maxRetries {
                    NSLog("🚫 20 attempts failed - resuming mDNS discovery...")
                    await resumeDiscoveryAfterFailure()
                }
            }
        }
    }
    
    @MainActor
    private func resumeDiscoveryAfterFailure() {
        stopRetry()
        
        // Reprendre mDNS discovery
        if shouldConnect && !isConnected {
            startDiscovery()
        }
    }
    
    // MARK: - Connection
    
    @MainActor
    private func connectToMilo() async {
        guard shouldConnect && !isConnected else { return }
        
        NSLog("🔌 Connecting to Milo...")
        
        // Arrêter retry - on a trouvé Milo !
        stopRetry()
        
        // Connecter WebSocket
        await connectWebSocket()
    }
    
    private func connectWebSocket() async {
        let urlString = "ws://\(host):\(wsPort)/ws"
        guard let url = URL(string: urlString) else {
            NSLog("❌ Invalid WebSocket URL")
            return
        }
        
        // Nettoyer l'ancienne connexion
        cleanupConnection()
        
        NSLog("🌐 Connecting WebSocket to \(urlString)...")
        webSocketTask = urlSession?.webSocketTask(with: url)
        webSocketTask?.resume()
        
        startListening()
    }
    
    private func cleanupConnection() {
        webSocketTask?.cancel()
        webSocketTask = nil
        apiService = nil
    }
    
    private func startListening() {
        webSocketTask?.receive { [weak self] result in
            switch result {
            case .success(let message):
                self?.handleWebSocketMessage(message)
                // Continuer à écouter si toujours connecté
                if self?.isConnected == true {
                    self?.startListening()
                }
                
            case .failure(let error):
                NSLog("❌ WebSocket error: \(error.localizedDescription)")
                DispatchQueue.main.async { [weak self] in
                    self?.handleDisconnection()
                }
            }
        }
    }
    
    private func handleWebSocketMessage(_ message: URLSessionWebSocketTask.Message) {
        switch message {
        case .string(let text):
            parseWebSocketMessage(text)
        case .data(let data):
            if let text = String(data: data, encoding: .utf8) {
                parseWebSocketMessage(text)
            }
        @unknown default:
            break
        }
    }
    
    private func parseWebSocketMessage(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let category = json["category"] as? String,
              let eventType = json["type"] as? String,
              let eventData = json["data"] as? [String: Any] else {
            return
        }
        
        DispatchQueue.main.async { [weak self] in
            switch category {
            case "system":
                if eventType == "state_changed" || eventType == "transition_complete" || eventType == "transition_start" {
                    self?.handleSystemStateChange(eventData)
                }
                
            case "volume":
                if eventType == "volume_changed" {
                    self?.handleVolumeChange(eventData)
                }
                
            case "plugin":
                if eventType == "state_changed" {
                    self?.handleSystemStateChange(eventData)
                }
                
            default:
                break
            }
        }
    }
    
    private func handleSystemStateChange(_ data: [String: Any]) {
        guard let fullState = data["full_state"] as? [String: Any] else { return }
        
        // CORRECTION : Ajout du paramètre targetSource manquant
        let targetSource = fullState["target_source"] as? String
        
        let state = MiloState(
            activeSource: fullState["active_source"] as? String ?? "none",
            pluginState: fullState["plugin_state"] as? String ?? "inactive",
            isTransitioning: fullState["transitioning"] as? Bool ?? false,
            targetSource: targetSource, // AJOUTÉ
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
    
    private func handleConnectionSuccess() {
        NSLog("🎉 Milo connected successfully!")
        
        isConnected = true
        
        // Créer l'API service
        apiService = MiloAPIService(host: host, port: httpPort)
        
        delegate?.miloDidConnect()
    }
    
    private func handleDisconnection() {
        NSLog("💔 Milo connection lost")
        
        cleanupConnection()
        
        if isConnected {
            isConnected = false
            delegate?.miloDidDisconnect()
        }
        
        // Reprendre mDNS discovery pour détecter quand Milo revient
        if shouldConnect {
            NSLog("📡 Resuming mDNS discovery...")
            startDiscovery()
        }
    }
    
    private func disconnect() {
        cleanupConnection()
        
        if isConnected {
            isConnected = false
            DispatchQueue.main.async { [weak self] in
                self?.delegate?.miloDidDisconnect()
            }
        }
    }
    
    deinit {
        stop()
    }
}

// MARK: - NetServiceBrowserDelegate
extension MiloConnectionManager: NetServiceBrowserDelegate {
    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        NSLog("🔍 Found service: \(service.name)")
        
        // Vérifier si c'est notre service milo
        let serviceName = service.name.lowercased()
        let hostName = service.hostName?.lowercased() ?? ""
        
        if (serviceName.contains("milo") || hostName.contains("milo")) && !isRetrying && !isConnected {
            NSLog("🎯 Found Milo service - starting rapid API tests...")
            startAPIRetry()
        }
    }
    
    func netServiceBrowser(_ browser: NetServiceBrowser, didRemove service: NetService, moreComing: Bool) {
        NSLog("📤 Service removed: \(service.name)")
        
        let serviceName = service.name.lowercased()
        let hostName = service.hostName?.lowercased() ?? ""
        
        if serviceName.contains("milo") || hostName.contains("milo") {
            // Arrêter retry si on était en train de tester
            if retryTimer != nil {
                NSLog("📡 Milo service removed during retry - resuming discovery...")
                stopRetry()
                if shouldConnect && !isConnected {
                    startDiscovery()
                }
            }
            
            // Gérer la déconnexion si on était connecté
            if isConnected {
                DispatchQueue.main.async { [weak self] in
                    self?.handleDisconnection()
                }
            }
        }
    }
    
    func netServiceBrowserWillSearch(_ browser: NetServiceBrowser) {
        NSLog("📡 mDNS browser will start searching...")
    }
    
    func netServiceBrowserDidStopSearch(_ browser: NetServiceBrowser) {
        NSLog("🛑 mDNS browser stopped searching")
    }
    
    func netServiceBrowser(_ browser: NetServiceBrowser, didNotSearch errorDict: [String : NSNumber]) {
        NSLog("❌ mDNS browser search failed: \(errorDict)")
    }
}

// MARK: - URLSessionWebSocketDelegate
extension MiloConnectionManager: URLSessionWebSocketDelegate {
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        NSLog("✅ WebSocket connected")
        
        DispatchQueue.main.async { [weak self] in
            self?.handleConnectionSuccess()
        }
    }
    
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        let reasonString = reason.flatMap { String(data: $0, encoding: .utf8) } ?? "Unknown"
        NSLog("🔌 WebSocket closed: \(closeCode.rawValue) - \(reasonString)")
        
        DispatchQueue.main.async { [weak self] in
            self?.handleDisconnection()
        }
    }
}
