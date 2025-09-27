import Foundation
import SwiftUI
import AppKit

protocol RocVADManagerDelegate: AnyObject {
    func rocVADSetupCompleted(success: Bool)
}

class RocVADManager: NSObject {
    weak var delegate: RocVADManagerDelegate?
    
    private let deviceName = "Milō"
    private let miloHost = "milo.local"
    private let sourcePort = 10001
    private let repairPort = 10002
    private let controlPort = 10003
    
    // Interface de progression (main thread uniquement)
    private var progressWindow: NSWindow?
    private var statusLabel: NSTextField?
    private var progressBar: NSProgressIndicator?
    
    func ensureSetup() {
        NSLog("🎯 RocVADManager: Starting setup verification...")
        
        // Vérification sur background thread
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let isInstalled = self?.checkRocVADInstallation() ?? false
            
            DispatchQueue.main.async {
                if isInstalled {
                    NSLog("✅ roc-vad already installed")
                    self?.checkAndConfigureDevice()
                } else {
                    NSLog("❓ roc-vad not installed - showing choice UI")
                    self?.showInitialChoiceAlert()
                }
            }
        }
    }
    
    // MARK: - Installation Check (background thread)
    
    private func checkRocVADInstallation() -> Bool {
        let rocVADPath = "/usr/local/bin/roc-vad"
        guard FileManager.default.fileExists(atPath: rocVADPath) else {
            NSLog("❌ roc-vad binary not found at \(rocVADPath)")
            return false
        }
        
        return testRocVADFunctionality()
    }
    
    private func testRocVADFunctionality() -> Bool {
        let task = Process()
        task.launchPath = "/usr/local/bin/roc-vad"
        task.arguments = ["info"]
        
        let semaphore = DispatchSemaphore(value: 0)
        var isWorking = false
        
        task.terminationHandler = { _ in
            isWorking = (task.terminationStatus == 0)
            semaphore.signal()
        }
        
        task.launch()
        semaphore.wait()
        
        if isWorking {
            NSLog("✅ roc-vad driver is functional")
        } else {
            NSLog("⚠️ roc-vad binary exists but driver not loaded")
        }
        
        return isWorking
    }
    
    // MARK: - Interface (main thread uniquement)
    
    private func showInitialChoiceAlert() {
        let alert = NSAlert()
        alert.messageText = "Configuration Milō Mac"
        alert.informativeText = "Milō peut utiliser l'audio de votre Mac comme source audio.\nVoulez-vous installer cette fonctionnalité ?"
        alert.addButton(withTitle: "Contrôleur + Audio Mac")
        alert.addButton(withTitle: "Contrôleur seulement")
        alert.alertStyle = .informational
        
        let response = alert.runModal()
        
        if response == .alertFirstButtonReturn {
            NSLog("🔧 User chose to install roc-vad")
            startInstallationWithProgress()
        } else {
            NSLog("✅ User chose controller only")
            completeSetup(success: true)
        }
    }
    
    private func startInstallationWithProgress() {
        createProgressWindow()
        
        // Installation sur background thread
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let success = self?.performRocVADInstallation() ?? false
            
            DispatchQueue.main.async {
                self?.hideProgressWindow()
                
                if success {
                    self?.showRestartChoiceAlert()
                } else {
                    self?.showErrorAlert()
                }
            }
        }
    }
    
    private func createProgressWindow() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 120),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        
        window.title = "Installation en cours"
        window.center()
        window.level = .floating
        
        let contentView = NSView(frame: window.contentView!.bounds)
        
        // Label de statut
        let label = NSTextField(labelWithString: "Installation de roc-vad...")
        label.alignment = .center
        label.font = .systemFont(ofSize: 13)
        label.frame = NSRect(x: 20, y: 70, width: 360, height: 20)
        label.isEditable = false
        label.isBordered = false
        label.backgroundColor = .clear
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
        // Toujours appeler depuis main thread
        statusLabel?.stringValue = message
    }
    
    private func hideProgressWindow() {
        progressBar?.stopAnimation(nil)
        progressWindow?.close()
        progressWindow = nil
        statusLabel = nil
        progressBar = nil
    }
    
    private func showRestartChoiceAlert() {
        let alert = NSAlert()
        alert.messageText = "Installation terminée"
        alert.informativeText = """
        L'installation de roc-vad est terminée avec succès !
        
        Pour que la sortie audio "Milō" apparaisse dans vos préférences système :
        1. Redémarrez votre Mac manuellement
        2. Relancez Milo Mac
        
        La sortie audio sera alors disponible et configurée automatiquement.
        """
        alert.addButton(withTitle: "OK")
        alert.alertStyle = .informational
        
        alert.runModal()
        completeSetup(success: true)
    }
    
    private func showErrorAlert() {
        let alert = NSAlert()
        alert.messageText = "Erreur d'installation"
        alert.informativeText = "L'installation de roc-vad a échoué. Voulez-vous réessayer ?"
        alert.addButton(withTitle: "Réessayer")
        alert.addButton(withTitle: "Continuer sans audio Mac")
        alert.alertStyle = .warning
        
        let response = alert.runModal()
        
        if response == .alertFirstButtonReturn {
            startInstallationWithProgress()
        } else {
            completeSetup(success: true)
        }
    }
    
    // MARK: - Installation Process (background thread uniquement)
    
    private func performRocVADInstallation() -> Bool {
        NSLog("🔧 Starting roc-vad installation...")
        
        DispatchQueue.main.async { [weak self] in
            self?.updateProgressStatus("Téléchargement et installation de roc-vad...")
        }
        
        let installSuccess = installRocVAD()
        if !installSuccess {
            return false
        }
        
        DispatchQueue.main.async { [weak self] in
            self?.updateProgressStatus("Vérification de l'installation...")
        }
        
        Thread.sleep(forTimeInterval: 1.0)
        
        // Vérifier que le binaire est installé
        let rocVADPath = "/usr/local/bin/roc-vad"
        let binaryExists = FileManager.default.fileExists(atPath: rocVADPath)
        
        if binaryExists {
            DispatchQueue.main.async { [weak self] in
                self?.updateProgressStatus("Installation terminée avec succès !")
            }
            Thread.sleep(forTimeInterval: 1.0)
            NSLog("✅ Installation completed successfully")
            return true
        } else {
            return false
        }
    }
    
    private func installRocVAD() -> Bool {
        let script = """
        do shell script "sudo /bin/bash -c \\"$(curl -fsSL https://raw.githubusercontent.com/roc-streaming/roc-vad/HEAD/install.sh)\\"" with administrator privileges
        """
        
        // Exécuter NSAppleScript directement sur le thread courant (background)
        let appleScript = NSAppleScript(source: script)
        appleScript?.executeAndReturnError(nil)
        
        Thread.sleep(forTimeInterval: 3.0)
        
        let rocVADPath = "/usr/local/bin/roc-vad"
        let binaryExists = FileManager.default.fileExists(atPath: rocVADPath)
        
        NSLog(binaryExists ? "✅ roc-vad binary successfully installed" : "❌ roc-vad binary not found after installation")
        
        return binaryExists
    }
    
    // MARK: - Device Configuration (background thread)
    
    private func checkAndConfigureDevice() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            NSLog("🔍 Checking existing Milō device...")
            
            let success = self?.ensureDeviceConfigured() ?? false
            
            DispatchQueue.main.async {
                self?.completeSetup(success: success)
            }
        }
    }
    
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
    
    // MARK: - System Actions
    
    private func restartMacNow() {
        // Fermer l'app proprement avant de redémarrer
        DispatchQueue.main.async { [weak self] in
            self?.completeSetup(success: true)
            
            // Attendre que l'app se ferme puis redémarrer
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                let script = """
                do shell script "sudo shutdown -r now" with administrator privileges
                """
                
                DispatchQueue.global().async {
                    let appleScript = NSAppleScript(source: script)
                    appleScript?.executeAndReturnError(nil)
                }
            }
        }
    }
    
    private func completeSetup(success: Bool) {
        delegate?.rocVADSetupCompleted(success: success)
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
