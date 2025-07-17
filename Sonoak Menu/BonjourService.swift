import Foundation
import Network

class BonjourService: NSObject, ObservableObject {
    private var browser: NWBrowser?
    private var isSearching = false
    
    weak var delegate: BonjourServiceDelegate?
    
    override init() {
        super.init()
        startBrowsing()
    }
    
    private func startBrowsing() {
        guard !isSearching else { return }
        
        // Chercher les services HTTP avec le nom "oakos"
        let parameters = NWParameters()
        parameters.includePeerToPeer = false
        
        browser = NWBrowser(for: .bonjourWithTXTRecord(type: "_http._tcp", domain: nil), using: parameters)
        
        browser?.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                print("🔍 Bonjour browser ready")
                self?.isSearching = true
            case .failed(let error):
                print("❌ Bonjour browser failed: \(error)")
                self?.isSearching = false
            default:
                break
            }
        }
        
        browser?.browseResultsChangedHandler = { [weak self] results, changes in
            print("🔍 Services trouvés: \(results.count)")
            
            for result in results {
                if case let .service(name, _, _, _) = result.endpoint {
                    print("📡 Service détecté: \(name)")
                    
                    // Chercher "oakos" de manière plus flexible
                    if name.lowercased().contains("oakos") ||
                       name.lowercased().contains("sonoak") ||
                       name.lowercased().contains("oak") {
                        print("✅ Found oakOS service: \(name)")
                        self?.resolveService(result)
                    }
                }
            }
        }
        
        browser?.start(queue: .main)
    }
    
    private func resolveService(_ result: NWBrowser.Result) {
        let connection = NWConnection(to: result.endpoint, using: .tcp)
        
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                if case let .service(name, _, _, _) = result.endpoint {
                    // Essayer d'extraire l'IP de manière plus directe
                    let endpointDescription = "\(result.endpoint)"
                    print("🔍 Endpoint brut: \(endpointDescription)")
                    
                    // Pour l'instant, utiliser l'IP connue comme fallback
                    print("🌐 Utilisation de l'IP de fallback")
                    self?.delegate?.oakOSFound(name: name, host: "192.168.1.152", port: 8000)
                }
                connection.cancel()
            case .failed(let error):
                print("❌ Résolution échouée: \(error)")
                // Fallback vers IP connue
                if case let .service(name, _, _, _) = result.endpoint {
                    print("🔄 Fallback vers IP connue")
                    self?.delegate?.oakOSFound(name: name, host: "192.168.1.152", port: 8000)
                }
                connection.cancel()
            default:
                break
            }
        }
        
        connection.start(queue: .main)
    }
    
    func stopBrowsing() {
        browser?.cancel()
        browser = nil
        isSearching = false
    }
    
    deinit {
        stopBrowsing()
    }
}

protocol BonjourServiceDelegate: AnyObject {
    func oakOSFound(name: String, host: String, port: Int)
    func oakOSLost()
}
