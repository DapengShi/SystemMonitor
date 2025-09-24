import AppKit
import Foundation

// Main application entry point
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory) // Hide from Dock
app.run()

