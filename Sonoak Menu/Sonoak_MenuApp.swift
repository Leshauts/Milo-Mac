import SwiftUI

@main
struct Sonoak_MenuApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var menuBarController: MenuBarController!
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Cacher l'icône du dock
        NSApp.setActivationPolicy(.accessory)
        
        // Créer l'item de menu bar
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        // Initialiser le contrôleur
        menuBarController = MenuBarController(statusItem: statusItem)
    }
}
