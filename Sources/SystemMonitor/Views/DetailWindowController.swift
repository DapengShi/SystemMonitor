import AppKit
import SwiftUI

class DetailWindowController: NSWindowController {
    // Singleton instance
    static let shared = DetailWindowController()
    
    private init() {
        // Create the SwiftUI view
        let detailView = DetailView()
        
        // Create the hosting view controller
        let hostingController = NSHostingController(rootView: detailView)
        
        // Create a window with the hosting controller
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1000, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        
        window.title = "System Monitor Details"
        window.contentViewController = hostingController
        window.center()
        window.setFrameAutosaveName("DetailWindow")
        window.isReleasedWhenClosed = false
        
        // Initialize with the window
        super.init(window: window)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func showWindow() {
        guard let window = window else { return }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
