import Foundation

struct MiloState {
    let activeSource: String
    let pluginState: String
    let isTransitioning: Bool     // GARDÉ pour compatibilité backend, mais NON UTILISÉ côté Mac
    let targetSource: String?     // SEUL INDICATEUR utilisé pour les spinners
    let multiroomEnabled: Bool
    let equalizerEnabled: Bool
    let metadata: [String: Any]
}

struct VolumeStatus {
    let volume: Int
    let mode: String
    let multiroomEnabled: Bool
}

class MiloAPIService {
    private let baseURL: String
    private let session: URLSession
    
    init(host: String, port: Int = 80) {
        self.baseURL = "http://\(host):\(port)"
        
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 3.0
        config.timeoutIntervalForResource = 5.0
        config.waitsForConnectivity = false
        self.session = URLSession(configuration: config)
    }
    
    func fetchState() async throws -> MiloState {
        guard let url = URL(string: "\(baseURL)/api/audio/state") else {
            throw APIError.invalidURL
        }
        
        let (data, response) = try await session.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw APIError.httpError
        }
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw APIError.invalidResponse
        }
        
        // NETTOYÉ : targetSource est maintenant LE seul indicateur de transition
        let targetSource = json["target_source"] as? String
        
        return MiloState(
            activeSource: json["active_source"] as? String ?? "none",
            pluginState: json["plugin_state"] as? String ?? "inactive",
            isTransitioning: json["transitioning"] as? Bool ?? false, // IGNORÉ côté Mac
            targetSource: targetSource, // SEUL INDICATEUR utilisé
            multiroomEnabled: json["multiroom_enabled"] as? Bool ?? false,
            equalizerEnabled: json["equalizer_enabled"] as? Bool ?? false,
            metadata: json["metadata"] as? [String: Any] ?? [:]
        )
    }
    
    func changeSource(_ source: String) async throws {
        guard let url = URL(string: "\(baseURL)/api/audio/source/\(source)") else {
            throw APIError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        
        let (_, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw APIError.httpError
        }
    }
    
    func setMultiroom(_ enabled: Bool) async throws {
        guard let url = URL(string: "\(baseURL)/api/routing/multiroom/\(enabled)") else {
            throw APIError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        
        let (_, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw APIError.httpError
        }
    }
    
    func setEqualizer(_ enabled: Bool) async throws {
        guard let url = URL(string: "\(baseURL)/api/routing/equalizer/\(enabled)") else {
            throw APIError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        
        let (_, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw APIError.httpError
        }
    }
    
    func getVolumeStatus() async throws -> VolumeStatus {
        guard let url = URL(string: "\(baseURL)/api/volume/status") else {
            throw APIError.invalidURL
        }
        
        let (data, response) = try await session.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw APIError.httpError
        }
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataDict = json["data"] as? [String: Any] else {
            throw APIError.invalidResponse
        }
        
        return VolumeStatus(
            volume: dataDict["volume"] as? Int ?? 0,
            mode: dataDict["mode"] as? String ?? "unknown",
            multiroomEnabled: dataDict["multiroom_enabled"] as? Bool ?? false
        )
    }
    
    func setVolume(_ volume: Int) async throws {
        guard let url = URL(string: "\(baseURL)/api/volume/set") else {
            throw APIError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = ["volume": volume, "show_bar": false]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (_, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw APIError.httpError
        }
    }
    
    func adjustVolume(_ delta: Int) async throws {
        guard let url = URL(string: "\(baseURL)/api/volume/adjust") else {
            throw APIError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = ["delta": delta, "show_bar": false]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (_, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw APIError.httpError
        }
    }
}

enum APIError: Error {
    case invalidURL
    case httpError
    case invalidResponse
}
