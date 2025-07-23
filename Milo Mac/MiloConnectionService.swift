import Foundation
import Network

class MiloConnectionService: NSObject, ObservableObject {
    private let miloHost = "milo.local"
    private let miloPort = 80
    private var connectionMonitor: NWPathMonitor?
    private var isConnected = false
    private var connectionTimer: Timer?
    
    weak var delegate: MiloConnectionDelegate?
    
    override init() {
        super.init()
        NSLog("🌐 MiloConnectionService initializing...")
        startNetworkMonitoring()
        tryConnection()
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
    
    func tryConnection() {
        NSLog("🔄 Attempting connection to \(miloHost):\(miloPort)")
        
        let host = NWEndpoint.Host(miloHost)
        guard let port = NWEndpoint.Port(rawValue: UInt16(miloPort)) else {
            NSLog("❌ Invalid port: \(miloPort)")
            return
        }
        
        let endpoint = NWEndpoint.hostPort(host: host, port: port)
        let connection = NWConnection(to: endpoint, using: .tcp)
        
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                NSLog("✅ Connected to Milo at \(self?.miloHost ?? "unknown"):\(self?.miloPort ?? 0)")
                connection.cancel()
                
                DispatchQueue.main.async {
                    self?.isConnected = true
                    self?.delegate?.miloFound(host: self?.miloHost ?? "milo.local", port: self?.miloPort ?? 80)
                }
                
            case .failed(let error):
                NSLog("❌ Connection failed: \(error)")
                connection.cancel()
                
                DispatchQueue.main.async {
                    self?.isConnected = false
                    self?.delegate?.miloLost()
                    
                    // Retry après 5 secondes
                    self?.scheduleRetry()
                }
                
            case .cancelled:
                NSLog("🛑 Connection cancelled")
                
            default:
                NSLog("🤷 Connection state: \(state)")
            }
        }
        
        connection.start(queue: .main)
    }
    
    private func scheduleRetry() {
        connectionTimer?.invalidate()
        connectionTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { [weak self] _ in
            self?.tryConnection()
        }
    }
    
    private func handleDisconnection() {
        if isConnected {
            isConnected = false
            delegate?.miloLost()
        }
    }
    
    func forceReconnect() {
        NSLog("🔄 Force reconnection requested")
        tryConnection()
    }
    
    deinit {
        connectionMonitor?.cancel()
        connectionTimer?.invalidate()
    }
}

protocol MiloConnectionDelegate: AnyObject {
    func miloFound(host: String, port: Int)
    func miloLost()
}
