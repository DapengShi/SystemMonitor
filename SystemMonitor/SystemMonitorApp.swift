// Copyright 2024 SystemMonitor Contributors
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import SwiftUI
import Cocoa

@main
struct SystemMonitorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 900, minHeight: 700)
        }
        .windowStyle(.titleBar)
        .windowResizability(.contentSize)
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var popover: NSPopover!
    var systemStatsManager: SystemStatsManager!
    var processManager: ProcessManager!
    var mainWindow: NSWindow?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Initialize managers
        systemStatsManager = SystemStatsManager()
        processManager = ProcessManager()
        
        // Setup status bar item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem.button {
            updateStatusBarButton(button)
        }
        
        // Setup popover
        popover = NSPopover()
        popover.contentSize = NSSize(width: 300, height: 200)
        popover.behavior = .transient
        
        // Update status bar every 2 seconds
        Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            if let button = self.statusItem.button {
                self.updateStatusBarButton(button)
            }
        }
        
        // Create menu for right-click
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Open Full Monitor", action: #selector(openFullMonitor), keyEquivalent: "o"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q"))
        statusItem.menu = menu
    }
    
    func updateStatusBarButton(_ button: NSStatusBarButton) {
        let cpuUsage = systemStatsManager.cpuUsage
        let memoryUsage = systemStatsManager.memoryUsage
        
        // Change color based on usage
        let hasHighUsage = cpuUsage > 80 || memoryUsage > 80
        let textColor = hasHighUsage ? NSColor.red : NSColor.labelColor
        
        let attributedTitle = NSAttributedString(
            string: String(format: "CPU:%.0f%% MEM:%.0f%%", cpuUsage, memoryUsage),
            attributes: [
                .foregroundColor: textColor,
                .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: hasHighUsage ? .bold : .regular)
            ]
        )
        
        button.attributedTitle = attributedTitle
        button.toolTip = String(format: "CPU: %.1f%%\nMemory: %.1f%%\nNetwork: ↓%.1f KB/s ↑%.1f KB/s",
                               cpuUsage, memoryUsage, systemStatsManager.networkIn, systemStatsManager.networkOut)
    }
    
    @objc func togglePopover(_ sender: AnyObject?) {
        if let button = statusItem.button {
            if popover.isShown {
                popover.performClose(sender)
            } else {
                popover.contentViewController = NSHostingController(rootView: StatusBarView(systemStats: systemStatsManager, processManager: processManager))
                popover.show(relativeTo: button.bounds, of: button, preferredEdge: NSRectEdge.minY)
            }
        }
    }
    
    @objc func openFullMonitor() {
        if mainWindow == nil {
            let contentView = SystemMonitorView(systemStats: systemStatsManager, processManager: processManager)
            
            mainWindow = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 900, height: 700),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            
            mainWindow?.title = "System Monitor"
            mainWindow?.contentView = NSHostingController(rootView: contentView).view
            mainWindow?.center()
        }
        
        mainWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    @objc func quitApp() {
        NSApplication.shared.terminate(self)
    }
}

struct StatusBarView: View {
    @ObservedObject var systemStats: SystemStatsManager
    @ObservedObject var processManager: ProcessManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "cpu")
                    .foregroundColor(.orange)
                Text(String(format: "CPU: %.1f%%", systemStats.cpuUsage))
                    .font(.system(size: 12, design: .monospaced))
            }
            
            HStack {
                Image(systemName: "memorychip")
                    .foregroundColor(.blue)
                Text(String(format: "Memory: %.1f%%", systemStats.memoryUsage))
                    .font(.system(size: 12, design: .monospaced))
            }
            
            HStack {
                Image(systemName: "arrow.down.circle")
                    .foregroundColor(.green)
                Text(String(format: "↓ %.1f KB/s", systemStats.networkIn))
                    .font(.system(size: 12, design: .monospaced))
            }
            
            HStack {
                Image(systemName: "arrow.up.circle")
                    .foregroundColor(.red)
                Text(String(format: "↑ %.1f KB/s", systemStats.networkOut))
                    .font(.system(size: 12, design: .monospaced))
            }
            
            Divider()
            
            // Top processes
            VStack(alignment: .leading, spacing: 4) {
                Text("Top Processes")
                    .font(.headline)
                    .fontSize(12)
                
                ForEach(processManager.processes.prefix(5), id: \.pid) { process in
                    HStack {
                        Text("\(process.name)")
                            .font(.system(size: 10))
                            .lineLimit(1)
                        Spacer()
                        Text(String(format: "%.1f%%", process.cpu))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(process.cpu > 80 ? .red : .primary)
                    }
                }
            }
            
            Divider()
            
            Button("Open Full Monitor") {
                if let appDelegate = NSApplication.shared.delegate as? AppDelegate {
                    appDelegate.openFullMonitor()
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .frame(maxWidth: .infinity)
        }
        .padding()
        .frame(width: 280)
    }
}

struct ContentView: View {
    @StateObject private var systemStats = SystemStatsManager()
    @StateObject private var processManager = ProcessManager()
    
    var body: some View {
        SystemMonitorView(systemStats: systemStats, processManager: processManager)
    }
}