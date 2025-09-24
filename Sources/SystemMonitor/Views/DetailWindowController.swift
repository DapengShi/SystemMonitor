import AppKit
import SwiftUI

private final class DetailWindow: NSWindow {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.type == .keyDown else {
            return super.performKeyEquivalent(with: event)
        }

        let commandOnly = event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command
        guard commandOnly, let key = event.charactersIgnoringModifiers?.lowercased() else {
            return super.performKeyEquivalent(with: event)
        }

        switch key {
        case "w":
            performClose(nil)
            return true
        case "a":
            if NSApp.sendAction(#selector(NSResponder.selectAll(_:)), to: nil, from: self) {
                return true
            }
        case "c":
            if NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: self) {
                return true
            }
        case "x":
            if NSApp.sendAction(#selector(NSText.cut(_:)), to: nil, from: self) {
                return true
            }
        case "v":
            if NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: self) {
                return true
            }
        default:
            break
        }

        return super.performKeyEquivalent(with: event)
    }
}

class DetailWindowController: NSWindowController {
    // Singleton instance
    static let shared = DetailWindowController()
    
    private init() {
        // Create the SwiftUI view
        let detailView = DetailView()
        
        // Create the hosting view controller
        let hostingController = NSHostingController(rootView: detailView)
        
        // Create a window with the hosting controller
        let window = DetailWindow(
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
