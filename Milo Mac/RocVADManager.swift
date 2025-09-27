import Foundation
import SwiftUI
import AppKit

class RocVADManager {
    
    private let deviceName = "Milō"
    private let miloHost = "milo.local"
    private let sourcePort = 10001
    private let repairPort = 10002
    private let controlPort = 10003
    
    // Fenêtre de progression simple
    private var progressWindow: NSWindow?
    private var statusLabel: NSTextField?
    private var progressBar: NSProgressIndicator?
    
    // MARK: - Public Interface
    
    func checkInstallation() -> Bool {
        NSLog("🔍 Checking roc-vad installation...")
        
        let rocVADPath = "/usr/local/bin/roc-vad"
        guard FileManager.default.fileExists(atPath: rocVADPath) else {
            NSLog("❌ roc-vad binary not found")
            return false
        }
        
        // Test simple de fonctionnalité (driver chargé)
        let task = Process()
        task.launchPath = rocVADPath
        task.arguments = ["info"]
        task.standardOutput = Pipe()
        task.standardError = Pipe()
        
        task.launch()
        task.waitUntilExit()
        
        let isWorking = (task.terminationStatus == 0)
        NSLog(isWorking ? "✅ roc-vad is functional" : "⚠️ roc-vad binary exists but driver not loaded")
        
        return isWorking
    }
    
    func isDriverLoaded() -> Bool {
        let rocVADPath = "/usr/local/bin/roc-vad"
        guard FileManager.default.fileExists(atPath: rocVADPath) else {
            return false
        }
        
        let task = Process()
        task.launchPath = rocVADPath
        task.arguments = ["info"]
        task.standardOutput = Pipe()
        task.standardError = Pipe()
        
        task.launch()
        task.waitUntilExit()
        
        return (task.terminationStatus == 0)
    }
    
    func performInstallation(completion: @escaping (Bool) -> Void) {
        NSLog("🔧 Starting roc-vad installation...")
        
        // Créer fenêtre de progression
        createProgressWindow()
        
        // Installation en background mais avec UI sur main thread
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let installSuccess = self?.installRocVAD() ?? false
            
            DispatchQueue.main.async {
                self?.hideProgressWindow()
                completion(installSuccess)
            }
        }
    }
    
    func configureDeviceOnly(completion: @escaping (Bool) -> Void) {
        NSLog("🔧 Configuring Milō audio device only...")
        
        // Créer fenêtre de progression
        createProgressWindow()
        updateProgressStatus("Configuration du dispositif audio Milō...")
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let success = self?.ensureDeviceConfigured() ?? false
            
            DispatchQueue.main.async {
                self?.hideProgressWindow()
                completion(success)
            }
        }
    }
    
    // MARK: - Installation Process
    
    private func installRocVAD() -> Bool {
        NSLog("📦 Installing roc-vad...")
        
        updateProgressStatus("Téléchargement et installation de roc-vad...")
        
        let script = """
        do shell script "sudo /bin/bash -c \\"$(curl -fsSL https://raw.githubusercontent.com/roc-streaming/roc-vad/HEAD/install.sh)\\"" with administrator privileges
        """
        
        // Exécuter l'installation
        DispatchQueue.main.sync {
            let appleScript = NSAppleScript(source: script)
            appleScript?.executeAndReturnError(nil)
        }
        
        // Attendre un peu pour que l'installation se termine
        Thread.sleep(forTimeInterval: 3.0)
        
        updateProgressStatus("Vérification de l'installation...")
        Thread.sleep(forTimeInterval: 1.0)
        
        // Vérifier que l'installation a réussi
        let rocVADPath = "/usr/local/bin/roc-vad"
        let success = FileManager.default.fileExists(atPath: rocVADPath)
        
        if success {
            updateProgressStatus("Installation terminée !")
            Thread.sleep(forTimeInterval: 1.0)
            NSLog("✅ roc-vad installation completed successfully")
        } else {
            NSLog("❌ roc-vad installation failed")
        }
        
        return success
    }
    
    // MARK: - Progress Window
    
    private func createProgressWindow() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 120),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        
        window.title = "Installation Milō"
        window.center()
        window.level = .floating
        window.isReleasedWhenClosed = false
        
        let contentView = NSView(frame: window.contentView!.bounds)
        
        // Label de statut
        let label = NSTextField(labelWithString: "Préparation de l'installation...")
        label.alignment = .center
        label.font = .systemFont(ofSize: 13)
        label.frame = NSRect(x: 20, y: 70, width: 360, height: 20)
        contentView.addSubview(label)
        statusLabel = label
        
        // Barre de progression
        let progress = NSProgressIndicator()
        progress.style = .bar
        progress.isIndeterminate = true
        progress.frame = NSRect(x: 50, y: 30, width: 300, height: 20)
        progress.startAnimation(nil)
        contentView.addSubview(progress)
        progressBar = progress
        
        window.contentView = contentView
        window.makeKeyAndOrderFront(nil)
        
        progressWindow = window
    }
    
    private func updateProgressStatus(_ message: String) {
        DispatchQueue.main.async { [weak self] in
            self?.statusLabel?.stringValue = message
        }
    }
    
    private func hideProgressWindow() {
        progressBar?.stopAnimation(nil)
        progressWindow?.close()
        progressWindow = nil
        statusLabel = nil
        progressBar = nil
    }
    
    // MARK: - Device Configuration
    
    private func ensureDeviceConfigured() -> Bool {
        let deviceInfo = getRocVADDeviceInfo()
        
        if let existingDevice = deviceInfo.first(where: { $0.name == deviceName }) {
            NSLog("✅ Found existing Milō device (index: \(existingDevice.index))")
            
            let isConfigured = checkDeviceConfiguration(deviceIndex: existingDevice.index)
            
            if isConfigured {
                NSLog("✅ Device already properly configured")
                return true
            } else {
                NSLog("🔧 Reconfiguring existing device...")
                return configureDevice(deviceIndex: existingDevice.index)
            }
        } else {
            NSLog("❌ No Milō device found, creating new one...")
            
            let deviceIndex = createMiloDevice()
            
            guard deviceIndex > 0 else {
                NSLog("❌ Failed to create Milō device")
                return false
            }
            
            NSLog("✅ Created new Milō device with index: \(deviceIndex)")
            return configureDevice(deviceIndex: deviceIndex)
        }
    }
    
    private func createMiloDevice() -> Int {
        let task = Process()
        task.launchPath = "/usr/local/bin/roc-vad"
        task.arguments = ["device", "add", "sender", "--name", deviceName]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        
        let semaphore = DispatchSemaphore(value: 0)
        var deviceIndex = 0
        
        task.terminationHandler = { _ in
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            deviceIndex = parseDeviceIndex(from: output)
            semaphore.signal()
        }
        
        task.launch()
        semaphore.wait()
        
        return deviceIndex
    }
    
    private func configureDevice(deviceIndex: Int) -> Bool {
        let task = Process()
        task.launchPath = "/usr/local/bin/roc-vad"
        task.arguments = [
            "device", "connect", "\(deviceIndex)",
            "--source", "rtp+rs8m://\(miloHost):\(sourcePort)",
            "--repair", "rs8m://\(miloHost):\(repairPort)",
            "--control", "rtcp://\(miloHost):\(controlPort)"
        ]
        
        let semaphore = DispatchSemaphore(value: 0)
        var success = false
        
        task.terminationHandler = { _ in
            success = (task.terminationStatus == 0)
            semaphore.signal()
        }
        
        task.launch()
        semaphore.wait()
        
        NSLog(success ? "✅ Device configured successfully" : "❌ Device configuration failed")
        return success
    }
    
    private func checkDeviceConfiguration(deviceIndex: Int) -> Bool {
        let task = Process()
        task.launchPath = "/usr/local/bin/roc-vad"
        task.arguments = ["device", "show", "\(deviceIndex)"]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        
        let semaphore = DispatchSemaphore(value: 0)
        var isConfigured = false
        
        task.terminationHandler = { _ in
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            isConfigured = output.contains(self.miloHost)
            semaphore.signal()
        }
        
        task.launch()
        semaphore.wait()
        
        return isConfigured
    }
    
    private func getRocVADDeviceInfo() -> [RocVADDeviceInfo] {
        let task = Process()
        task.launchPath = "/usr/local/bin/roc-vad"
        task.arguments = ["device", "list"]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        
        let semaphore = DispatchSemaphore(value: 0)
        var devices: [RocVADDeviceInfo] = []
        
        task.terminationHandler = { _ in
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            devices = parseDeviceList(from: output)
            semaphore.signal()
        }
        
        task.launch()
        semaphore.wait()
        
        return devices
    }
}

// MARK: - Supporting Types

struct RocVADDeviceInfo {
    let index: Int
    let name: String
}

// MARK: - Parsing Helpers

private func parseDeviceIndex(from output: String) -> Int {
    let pattern = #"device #(\d+)"#
    let regex = try? NSRegularExpression(pattern: pattern)
    let range = NSRange(output.startIndex..<output.endIndex, in: output)
    
    if let match = regex?.firstMatch(in: output, range: range),
       let indexRange = Range(match.range(at: 1), in: output) {
        return Int(String(output[indexRange])) ?? 0
    }
    
    return 0
}

private func parseDeviceList(from output: String) -> [RocVADDeviceInfo] {
    var devices: [RocVADDeviceInfo] = []
    
    let lines = output.components(separatedBy: .newlines)
    for line in lines {
        let components = line.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        if components.count >= 5,
           let index = Int(components[0]) {
            let name = components[4...].joined(separator: " ")
            devices.append(RocVADDeviceInfo(index: index, name: name))
        }
    }
    
    return devices
}
