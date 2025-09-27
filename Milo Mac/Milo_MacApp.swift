import SwiftUI
import ServiceManagement

@main
struct Milo_MacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var menuBarController: MenuBarController?
    var rocVADManager: RocVADManager?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        
        if NSApp.activationPolicy() != .accessory {
            NSApp.setActivationPolicy(.prohibited)
            NSApp.setActivationPolicy(.accessory)
        }
        
        NSLog("🚀 Milo Mac starting...")
        
        // Démarrer le processus d'installation/setup
        startSetupProcess()
    }
    
    private func startSetupProcess() {
        rocVADManager = RocVADManager()
        
        // Vérifier si roc-vad est installé ET que le driver est chargé
        if rocVADManager!.checkInstallation() {
            NSLog("✅ roc-vad installed and driver loaded - configuring device")
            configureDeviceAndStart()
        } else if FileManager.default.fileExists(atPath: "/usr/local/bin/roc-vad") {
            NSLog("⚠️ roc-vad installed but driver not loaded - waiting for initialization")
            waitForDriverAndConfigure()
        } else {
            NSLog("❓ roc-vad not installed - showing setup choice")
            showInitialChoice()
        }
    }
    
    private func waitForDriverAndConfigure() {
        NSLog("⏳ Waiting for roc-vad driver to initialize...")
        
        rocVADManager!.waitForDriverInitialization { [weak self] success in
            DispatchQueue.main.async {
                if success {
                    NSLog("✅ Driver initialized successfully - configuring device")
                    self?.configureDeviceAndStart()
                } else {
                    NSLog("⚠️ Driver initialization timeout - showing alternatives")
                    self?.showDriverTimeoutAlert()
                }
            }
        }
    }
    
    private func configureDeviceAndStart() {
        rocVADManager!.configureDeviceOnly { [weak self] success in
            if success {
                NSLog("✅ Device configured successfully")
            } else {
                NSLog("⚠️ Device configuration failed, continuing anyway")
            }
            
            self?.initializeMiloApp()
        }
    }
    
    private func showDriverTimeoutAlert() {
        let alert = NSAlert()
        alert.messageText = "Initialisation en cours"
        alert.informativeText = """
        Le driver audio roc-vad prend plus de temps que prévu à s'initialiser.
        
        Vous pouvez continuer sans la fonctionnalité audio Mac ou redémarrer pour réessayer.
        """
        alert.addButton(withTitle: "Continuer sans audio Mac")
        alert.addButton(withTitle: "Redémarrer maintenant")
        alert.alertStyle = .informational
        
        let response = alert.runModal()
        
        if response == .alertFirstButtonReturn {
            // Continuer sans audio Mac
            initializeMiloApp()
        } else {
            // Redémarrer
            restartMac()
        }
    }
    
    private func showDriverNotLoadedAlert() {
        let alert = NSAlert()
        alert.messageText = "Redémarrage requis"
        alert.informativeText = """
        roc-vad est installé mais le driver audio n'est pas encore chargé.
        
        Veuillez redémarrer votre Mac pour que la sortie audio "Milō" soit disponible.
        """
        alert.addButton(withTitle: "Redémarrer maintenant")
        alert.addButton(withTitle: "Continuer sans audio Mac")
        alert.alertStyle = .informational
        
        let response = alert.runModal()
        
        if response == .alertFirstButtonReturn {
            restartMac()
        } else {
            initializeMiloApp()
        }
    }
    
    private func showInitialChoice() {
        let alert = NSAlert()
        alert.messageText = "Configuration Milō Mac"
        alert.informativeText = "Milō peut utiliser l'audio de votre Mac comme source audio.\nVoulez-vous installer cette fonctionnalité ?"
        alert.addButton(withTitle: "Contrôleur + Audio Mac")
        alert.addButton(withTitle: "Contrôleur seulement")
        alert.alertStyle = .informational
        
        let response = alert.runModal()
        
        if response == .alertFirstButtonReturn {
            NSLog("🔧 User chose to install roc-vad")
            startInstallationProcess()
        } else {
            NSLog("✅ User chose controller only")
            initializeMiloApp()
        }
    }
    
    private func startInstallationProcess() {
        guard let rocVADManager = rocVADManager else {
            initializeMiloApp()
            return
        }
        
        // Installer avec retour visuel
        rocVADManager.performInstallation { [weak self] success in
            DispatchQueue.main.async {
                if success {
                    self?.showRestartChoice()
                } else {
                    self?.showInstallationError()
                }
            }
        }
    }
    
    private func showRestartChoice() {
        let alert = NSAlert()
        alert.messageText = "Installation terminée"
        alert.informativeText = """
        L'installation de roc-vad est terminée avec succès !
        
        Pour que la sortie audio "Milō" soit disponible, votre Mac doit redémarrer.
        
        Souhaitez-vous que Milo Mac se lance automatiquement au démarrage pour configurer le dispositif audio ?
        """
        alert.addButton(withTitle: "Redémarrer + Lancement auto")
        alert.addButton(withTitle: "Redémarrer seulement")
        alert.addButton(withTitle: "Redémarrer plus tard")
        alert.alertStyle = .informational
        
        let response = alert.runModal()
        
        switch response {
        case .alertFirstButtonReturn:
            // Activer launch at login puis redémarrer
            enableLaunchAtLogin()
            restartMac()
            
        case .alertSecondButtonReturn:
            // Redémarrer sans launch at login
            restartMac()
            
        default:
            // Redémarrer plus tard - quitter l'app
            NSLog("✅ User chose to restart later - quitting app")
            NSApplication.shared.terminate(nil)
        }
    }
    
    private func showInstallationError() {
        let alert = NSAlert()
        alert.messageText = "Erreur d'installation"
        alert.informativeText = "L'installation de roc-vad a échoué. Voulez-vous réessayer ou continuer sans audio Mac ?"
        alert.addButton(withTitle: "Réessayer")
        alert.addButton(withTitle: "Continuer sans audio Mac")
        alert.alertStyle = .warning
        
        let response = alert.runModal()
        
        if response == .alertFirstButtonReturn {
            startInstallationProcess()
        } else {
            initializeMiloApp()
        }
    }
    
    private func enableLaunchAtLogin() {
        NSLog("🔧 Enabling launch at login...")
        
        if #available(macOS 13.0, *) {
            do {
                try SMAppService.mainApp.register()
                NSLog("✅ Launch at login enabled")
            } catch {
                NSLog("❌ Failed to enable launch at login: \(error)")
            }
        } else {
            // Fallback pour macOS plus anciens
            let bundleIdentifier = Bundle.main.bundleIdentifier ?? ""
            SMLoginItemSetEnabled(bundleIdentifier as CFString, true)
            NSLog("✅ Launch at login enabled (legacy)")
        }
    }
    
    private func isLaunchAtLoginEnabled() -> Bool {
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        } else {
            return false
        }
    }
    
    private func restartMac() {
        NSLog("🔄 Restarting Mac...")
        
        let script = """
        do shell script "sudo shutdown -r now" with administrator privileges
        """
        
        let appleScript = NSAppleScript(source: script)
        appleScript?.executeAndReturnError(nil)
    }
    
    private func initializeMiloApp() {
        NSLog("🎯 Initializing Milo app interface...")
        
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        menuBarController = MenuBarController(statusItem: statusItem!)
        
        NSLog("✅ Milo Mac ready")
    }
    
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        return false
    }
}
