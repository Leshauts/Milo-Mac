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

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var menuBarController: MenuBarController!
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Cacher l'icône du dock - méthode renforcée
        NSApp.setActivationPolicy(.accessory)
        
        // Alternative si la première méthode ne fonctionne pas
        if NSApp.activationPolicy() != .accessory {
            NSApp.setActivationPolicy(.prohibited)
            NSApp.setActivationPolicy(.accessory)
        }
        
        // Créer l'item de menu bar
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        // Initialiser le contrôleur
        menuBarController = MenuBarController(statusItem: statusItem)
    }
    
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // Empêcher l'apparition dans le dock lors de la réouverture
        return false
    }
}
