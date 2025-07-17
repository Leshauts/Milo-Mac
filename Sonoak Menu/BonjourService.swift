import Foundation
import Network

class BonjourService: NSObject, ObservableObject {
    private var browser: NWBrowser?
    private var isSearching = false
    private var oakOSServiceName: String?
    
    weak var delegate: BonjourServiceDelegate?
    
    override init() {
        super.init()
        NSLog("🔍 BonjourService initializing...")
        startBrowsing()
    }
    
    private func startBrowsing() {
        guard !isSearching else {
            NSLog("⚠️ Already searching, skipping")
            return
        }
        
        NSLog("🔍 Starting Bonjour browser...")
        
        let parameters = NWParameters()
        parameters.includePeerToPeer = false
        
        browser = NWBrowser(for: .bonjourWithTXTRecord(type: "_http._tcp", domain: nil), using: parameters)
        
        browser?.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                NSLog("✅ Bonjour browser ready")
                self?.isSearching = true
            case .failed(let error):
                NSLog("❌ Bonjour browser failed: \(error)")
                self?.isSearching = false
                // Redémarrer après un délai
                DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
                    self?.startBrowsing()
                }
            case .cancelled:
                NSLog("🛑 Bonjour browser cancelled")
                self?.isSearching = false
            default:
                NSLog("🤷 Bonjour browser state: \(state)")
                break
            }
        }
        
        browser?.browseResultsChangedHandler = { [weak self] results, changes in
            print("🔍 Browse results changed - Total: \(results.count)")
            
            // Traiter uniquement les changements
            for change in changes {
                switch change {
                case .added(let result):
                    self?.handleServiceAdded(result)
                    
                case .removed(let result):
                    self?.handleServiceRemoved(result)
                    
                case .changed(_, let new, _):
                    print("📝 Service changed: \(new)")
                    
                    // Vérifier si c'est un service oakOS qui revient
                    if case let .service(name, _, _, _) = new.endpoint {
                        if self?.isOakOSService(name) == true && self?.oakOSServiceName == nil {
                            print("🔄 oakOS service reconnected via changed event: \(name)")
                            self?.oakOSServiceName = name
                            self?.resolveAndConnect(new)
                        }
                    }
                    
                case .identical:
                    print("📋 Service identical - no action needed")
                    
                @unknown default:
                    print("🤷 Unknown browse result change")
                }
            }
        }
        
        browser?.start(queue: .main)
    }
    
    private func handleServiceAdded(_ result: NWBrowser.Result) {
        if case let .service(name, _, _, _) = result.endpoint {
            NSLog("➕ Service detected: \(name)")
            
            // Chercher oakOS dans le nom du service
            if isOakOSService(name) {
                NSLog("✅ oakOS service found: \(name)")
                
                // Toujours connecter si on n'a pas de service actuel
                if oakOSServiceName == nil {
                    NSLog("🔄 Connecting to oakOS service: \(name)")
                    oakOSServiceName = name
                    resolveAndConnect(result)
                } else {
                    NSLog("⚠️ oakOS service already connected: \(oakOSServiceName!)")
                }
            }
        }
    }
    
    private func handleServiceRemoved(_ result: NWBrowser.Result) {
        if case let .service(name, _, _, _) = result.endpoint {
            NSLog("➖ Service removed: \(name)")
            
            // Vérifier si c'est notre service oakOS qui a disparu
            if let currentService = oakOSServiceName, currentService == name {
                NSLog("❌ Our oakOS service disappeared: \(name)")
                oakOSServiceName = nil
                delegate?.oakOSLost()
            }
        }
    }
    
    private func isOakOSService(_ name: String) -> Bool {
        let nameLower = name.lowercased()
        return nameLower.contains("oakos") ||
               nameLower.contains("oak") ||
               nameLower.contains("sonoak")
    }
    
    private func resolveAndConnect(_ result: NWBrowser.Result) {
        if case let .service(name, _, _, _) = result.endpoint {
            NSLog("🌐 Service resolved: \(name)")
            
            // Utiliser directement l'IP connue et le port 8000
            // La résolution Bonjour a des problèmes avec les ports
            NSLog("🔄 Using fallback IP and port")
            delegate?.oakOSFound(name: name, host: "192.168.1.188", port: 8000)
        }
    }
    
    private func extractHostFromEndpoint(_ endpoint: NWEndpoint) -> (host: String, port: Int)? {
        let description = "\(endpoint)"
        
        // Pattern pour extraire IP:port
        let ipPattern = #"(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}):(\d+)"#
        
        if let regex = try? NSRegularExpression(pattern: ipPattern),
           let match = regex.firstMatch(in: description, range: NSRange(description.startIndex..., in: description)) {
            
            let ipRange = Range(match.range(at: 1), in: description)!
            let portRange = Range(match.range(at: 2), in: description)!
            
            let host = String(description[ipRange])
            let port = Int(String(description[portRange])) ?? 8000
            
            return (host: host, port: port)
        }
        
        return nil
    }
    
    func stopBrowsing() {
        browser?.cancel()
        browser = nil
        isSearching = false
        oakOSServiceName = nil
    }
    
    deinit {
        stopBrowsing()
    }
}

protocol BonjourServiceDelegate: AnyObject {
    func oakOSFound(name: String, host: String, port: Int)
    func oakOSLost()
}
