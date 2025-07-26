import Foundation
import Network

class MiloConnectionService: NSObject, ObservableObject {
    private let miloHost = "milo.local"
    private let miloPort = 80
    private var connectionMonitor: NWPathMonitor?
    private var isConnected = false
    private var connectionTimer: Timer?
    private var healthCheckTimer: Timer?
    
    // Nouveaux paramètres pour améliorer la détection
    private let connectionCheckInterval: TimeInterval = 3.0  // Vérification plus fréquente
    private let healthCheckInterval: TimeInterval = 10.0    // Vérification santé API
    private let connectionTimeout: TimeInterval = 5.0       // Timeout plus court
    
    weak var delegate: MiloConnectionDelegate?
    
    override init() {
        super.init()
        NSLog("🌐 MiloConnectionService initializing...")
        startNetworkMonitoring()
        startConnectionMonitoring()
        startHealthCheck()
    }
    
    private func startNetworkMonitoring() {
        connectionMonitor = NWPathMonitor()
        
        connectionMonitor?.pathUpdateHandler = { [weak self] path in
            if path.status == .satisfied {
                NSLog("📶 Network available, trying connection...")
                DispatchQueue.main.async {
                    self?.tryConnection()
                }
            } else {
                NSLog("📵 Network unavailable")
                DispatchQueue.main.async {
                    self?.handleDisconnection()
                }
            }
        }
        
        let queue = DispatchQueue(label: "NetworkMonitor")
        connectionMonitor?.start(queue: queue)
    }
    
    // NOUVEAU : Monitoring continu de la connexion
    private func startConnectionMonitoring() {
        connectionTimer = Timer.scheduledTimer(withTimeInterval: connectionCheckInterval, repeats: true) { [weak self] _ in
            if self?.isConnected == false {
                self?.tryConnection()
            }
        }
    }
    
    // NOUVEAU : Health check de l'API pour détecter les services défaillants
    private func startHealthCheck() {
        healthCheckTimer = Timer.scheduledTimer(withTimeInterval: healthCheckInterval, repeats: true) { [weak self] _ in
            if self?.isConnected == true {
                self?.performHealthCheck()
            }
        }
    }
    
    func tryConnection() {
        NSLog("🔄 Attempting connection to \(miloHost):\(miloPort)")
        
        // AMÉLIORATION : Test TCP + test API en parallèle
        Task {
            let tcpSuccess = await testTCPConnection()
            
            if tcpSuccess {
                let apiSuccess = await testAPIConnection()
                
                await MainActor.run {
                    if apiSuccess && !self.isConnected {
                        self.connectToMilo()
                    } else if !apiSuccess && self.isConnected {
                        self.handleDisconnection()
                    }
                }
            } else {
                await MainActor.run {
                    self.handleDisconnection()
                }
            }
        }
    }
    
    // NOUVEAU : Test TCP asynchrone avec timeout
    private func testTCPConnection() async -> Bool {
        return await withCheckedContinuation { continuation in
            let host = NWEndpoint.Host(miloHost)
            guard let port = NWEndpoint.Port(rawValue: UInt16(miloPort)) else {
                continuation.resume(returning: false)
                return
            }
            
            let endpoint = NWEndpoint.hostPort(host: host, port: port)
            let connection = NWConnection(to: endpoint, using: .tcp)
            
            var hasResumed = false
            
            connection.stateUpdateHandler = { state in
                guard !hasResumed else { return }
                
                switch state {
                case .ready:
                    hasResumed = true
                    connection.cancel()
                    continuation.resume(returning: true)
                    
                case .failed(_):
                    hasResumed = true
                    connection.cancel()
                    continuation.resume(returning: false)
                    
                default:
                    break
                }
            }
            
            connection.start(queue: .global())
            
            // Timeout
            DispatchQueue.global().asyncAfter(deadline: .now() + connectionTimeout) {
                guard !hasResumed else { return }
                hasResumed = true
                connection.cancel()
                continuation.resume(returning: false)
            }
        }
    }
    
    // NOUVEAU : Test de l'API pour s'assurer que le service fonctionne
    private func testAPIConnection() async -> Bool {
        guard let url = URL(string: "http://\(miloHost):\(miloPort)/api/audio/state") else {
            return false
        }
        
        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = connectionTimeout
            
            let (_, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse {
                return httpResponse.statusCode == 200
            }
            return false
        } catch {
            NSLog("❌ API test failed: \(error.localizedDescription)")
            return false
        }
    }
    
    // NOUVEAU : Health check périodique de l'API
    private func performHealthCheck() {
        Task {
            let isHealthy = await testAPIConnection()
            
            await MainActor.run {
                if !isHealthy && self.isConnected {
                    NSLog("💔 Health check failed - service appears down")
                    self.handleDisconnection()
                }
            }
        }
    }
    
    private func connectToMilo() {
        if isConnected { return }
        
        isConnected = true
        NSLog("✅ Connected to Milo at \(miloHost):\(miloPort)")
        delegate?.miloFound(host: miloHost, port: miloPort)
    }
    
    private func handleDisconnection() {
        if !isConnected { return }
        
        isConnected = false
        NSLog("❌ Disconnected from Milo")
        
        // CORRECTION : Notification immédiate
        DispatchQueue.main.async { [weak self] in
            self?.delegate?.miloLost()
        }
    }
    
    func forceReconnect() {
        NSLog("🔄 Force reconnection requested")
        isConnected = false
        tryConnection()
    }
    
    // NOUVEAU : Méthode pour vérifier l'état de connexion depuis l'extérieur
    func getCurrentConnectionState() -> Bool {
        return isConnected
    }
    
    deinit {
        connectionMonitor?.cancel()
        connectionTimer?.invalidate()
        healthCheckTimer?.invalidate()
    }
}

protocol MiloConnectionDelegate: AnyObject {
    func miloFound(host: String, port: Int)
    func miloLost()
}
