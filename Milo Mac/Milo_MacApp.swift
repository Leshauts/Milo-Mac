import SwiftUI

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
    var statusItem: NSStatusItem!
    var menuBarController: MenuBarController!
    var rocVADManager: RocVADManager!
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        
        if NSApp.activationPolicy() != .accessory {
            NSApp.setActivationPolicy(.prohibited)
            NSApp.setActivationPolicy(.accessory)
        }
        
        NSLog("🚀 Milo Mac starting...")
        
        setupRocVAD()
    }
    
    private func setupRocVAD() {
        NSLog("🔧 Setting up roc-vad...")
        
        rocVADManager = RocVADManager()
        rocVADManager.delegate = self
        rocVADManager.ensureSetup()
    }
    
    private func initializeMiloApp() {
        NSLog("🎯 Initializing Milo app interface...")
        
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        menuBarController = MenuBarController(statusItem: statusItem)
        
        NSLog("✅ Milo Mac ready")
    }
    
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        return false
    }
}

// MARK: - RocVADManagerDelegate
extension AppDelegate: RocVADManagerDelegate {
    nonisolated func rocVADSetupCompleted(success: Bool) {
        Task { @MainActor in
            if success {
                NSLog("✅ Setup completed successfully")
                self.initializeMiloApp()
            } else {
                NSLog("⚠️ Setup failed, continuing anyway...")
                self.initializeMiloApp()
            }
        }
    }
}
