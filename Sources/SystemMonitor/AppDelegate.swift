import AppKit
import Foundation
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var timer: Timer?
    private var processTimer: Timer?
    private let updateInterval: TimeInterval = 2.0
    private let processUpdateInterval: TimeInterval = 5.0
    private let systemStats = SystemStats()
    private let processSectionSeparator = NSMenuItem.separator()
    private let processPlaceholderItem: NSMenuItem = {
        let item = NSMenuItem(title: "Collecting process data...", action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }()
    
    // System stats
    private var cpuUsage: Double = 0.0
    private var memoryUsage: Double = 0.0
    private var uploadSpeed: Double = 0.0
    private var downloadSpeed: Double = 0.0
    
    // Process monitoring
    private var topProcesses: [ProcessInfo] = []
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Create the status item in the menu bar
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem.button {
            button.title = "Loading..."
        }
        
        // Create the menu
        setupMenu()
        
        // Start monitoring system stats
        startMonitoring()
    }
    
    func setupMenu() {
        let menu = NSMenu()
        
        menu.addItem(NSMenuItem(title: "CPU: 0%", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Memory: 0%", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Network: ↑0 KB/s ↓0 KB/s", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Top Processes", action: nil, keyEquivalent: ""))
        menu.addItem(processPlaceholderItem)
        menu.addItem(processSectionSeparator)
        
        // Add Open Details menu item
        let openDetailsItem = NSMenuItem(title: "Open Detailed View", action: #selector(openDetailView), keyEquivalent: "d")
        openDetailsItem.target = self
        menu.addItem(openDetailsItem)
        
        menu.addItem(NSMenuItem.separator())
        let quitItem = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        
        statusItem.menu = menu
    }
    
    func startMonitoring() {
        // Initial update
        updateStats()
        updateProcesses()
        
        // Set up timer for periodic updates
        timer = Timer.scheduledTimer(withTimeInterval: updateInterval, repeats: true) { [weak self] _ in
            self?.updateStats()
        }
        
        // Set up timer for process monitoring
        processTimer = Timer.scheduledTimer(withTimeInterval: processUpdateInterval, repeats: true) { [weak self] _ in
            self?.updateProcesses()
        }
    }
    
    func updateStats() {
        // Update CPU usage
        cpuUsage = systemStats.getCPUUsage()
        
        // Update memory usage
        memoryUsage = systemStats.getMemoryUsage()
        
        // Update network stats
        let networkStats = systemStats.getNetworkStats()
        uploadSpeed = networkStats.uploadSpeed
        downloadSpeed = networkStats.downloadSpeed
        
        // Update the menu items
        updateMenuItems()
        
        // Update the status item
        updateStatusItem()
    }
    
    func updateProcesses() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let processes = self.systemStats.getTopProcesses(limit: 10)
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.topProcesses = processes
                self.updateProcessMenuItems()
                self.updateStatusItem()
            }
        }
    }
    
    func updateMenuItems() {
        guard let menu = statusItem.menu else { return }
        
        // Update CPU menu item
        if let cpuItem = menu.item(at: 0) {
            cpuItem.title = String(format: "CPU: %.1f%%", cpuUsage * 100)
        }
        
        // Update Memory menu item
        if let memoryItem = menu.item(at: 1) {
            memoryItem.title = String(format: "Memory: %.1f%%", memoryUsage * 100)
        }
        
        // Update Network menu item
        if let networkItem = menu.item(at: 2) {
            let uploadText = systemStats.formatByteSpeed(uploadSpeed)
            let downloadText = systemStats.formatByteSpeed(downloadSpeed)
            networkItem.title = "Network: ↑\(uploadText) ↓\(downloadText)"
        }
    }
    
    func updateProcessMenuItems() {
        guard let menu = statusItem.menu else { return }
        
        guard
            let headerIndex = menu.items.firstIndex(where: { $0.title == "Top Processes" }),
            let separatorIndex = menu.items.firstIndex(of: processSectionSeparator)
        else { return }
        
        if separatorIndex - headerIndex > 1 {
            for index in stride(from: separatorIndex - 1, through: headerIndex + 1, by: -1) {
                menu.removeItem(at: index)
            }
        }
        
        guard let updatedSeparatorIndex = menu.items.firstIndex(of: processSectionSeparator) else { return }
        
        if topProcesses.isEmpty {
            if menu.items.firstIndex(of: processPlaceholderItem) == nil {
                menu.insertItem(processPlaceholderItem, at: updatedSeparatorIndex)
            }
            return
        }
        
        if menu.items.firstIndex(of: processPlaceholderItem) != nil {
            menu.removeItem(processPlaceholderItem)
        }
        
        var insertionIndex = updatedSeparatorIndex
        for process in topProcesses {
            let netUp = systemStats.formatByteSpeed(process.networkOutBytesPerSecond)
            let netDown = systemStats.formatByteSpeed(process.networkInBytesPerSecond)
            let diskRead = systemStats.formatByteSpeed(process.diskReadBytesPerSecond)
            let diskWrite = systemStats.formatByteSpeed(process.diskWriteBytesPerSecond)
            let title = String(
                format: "%@ (CPU: %.1f%%, MEM: %.1f%%, NET: ↑%@ ↓%@, DISK: R%@ W%@)",
                process.name,
                process.cpuUsage,
                process.memoryUsage,
                netUp,
                netDown,
                diskRead,
                diskWrite
            )
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            
            if process.isAbnormal {
                let attributes: [NSAttributedString.Key: Any] = [
                    .foregroundColor: NSColor.red,
                    .font: NSFont.boldSystemFont(ofSize: NSFont.systemFontSize)
                ]
                item.attributedTitle = NSAttributedString(string: title, attributes: attributes)
            }
            
            menu.insertItem(item, at: insertionIndex)
            insertionIndex += 1
        }
    }
    
    func updateStatusItem() {
        guard let button = statusItem.button else { return }
        
        // Format the display text
        let cpuText = String(format: "CPU:%.0f%%", cpuUsage * 100)
        let memText = String(format: "MEM:%.0f%%", memoryUsage * 100)
        let netText = "↑\(systemStats.formatByteSpeedShort(uploadSpeed)) ↓\(systemStats.formatByteSpeedShort(downloadSpeed))"
        
        // Check if there are any abnormal processes
        let hasAbnormalProcesses = topProcesses.contains { $0.isAbnormal }
        
        // Create attributed string for status item
        let statusText = "\(cpuText) \(memText) \(netText)"
        let attributes: [NSAttributedString.Key: Any] = hasAbnormalProcesses ? 
            [.foregroundColor: NSColor.red] : 
            [.foregroundColor: NSColor.labelColor]
        
        button.attributedTitle = NSAttributedString(string: statusText, attributes: attributes)
    }
    
    @objc func openDetailView() {
        // Show the detail window
        DetailWindowController.shared.showWindow()
    }
    
    @objc func quit() {
        NSApplication.shared.terminate(nil)
    }
}
