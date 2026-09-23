import SwiftUI
import WidgetKit
import AppKit
import ServiceManagement

@main
struct FastfetchWidgetHostApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var timer: Timer?
    private let refreshInterval: TimeInterval = 10
    private let server = LocalFastfetchServer()

    private var launchAtLoginItem: NSMenuItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        registerLaunchAtLoginIfNeeded()
        server.start()
        setupStatusItem()
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "terminal", accessibilityDescription: "Fastfetch Widget")

        let menu = NSMenu()
        let refreshItem = NSMenuItem(title: "Refresh Now", action: #selector(refreshNow), keyEquivalent: "r")
        refreshItem.target = self
        menu.addItem(refreshItem)
        menu.addItem(NSMenuItem.separator())

        let loginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        loginItem.target = self
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(loginItem)
        launchAtLoginItem = loginItem

        menu.addItem(NSMenuItem.separator())
        let quitItem = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        item.menu = menu
        statusItem = item
    }

    private func registerLaunchAtLoginIfNeeded() {
        let status = SMAppService.mainApp.status
        guard status != .enabled, status != .requiresApproval else { return }
        do {
            try SMAppService.mainApp.register()
        } catch {
            FileHandle.standardError.write("Failed to register login item: \(error)\n".data(using: .utf8)!)
        }
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            print("Failed to toggle launch at login: \(error)")
        }
        launchAtLoginItem?.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }

    @objc private func refreshNow() {
        refresh()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func refresh() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            // Use whatever modules the user's own fastfetch config defines,
            // minus the two that don't render usefully in a widget: "break"
            // is a blank spacer line and "colors" is a block of coloured
            // rectangles with no text.
            let full = Self.runFastfetch(arguments: [
                "--logo", "none", "--pipe", "false",
                "--structure-disabled", "break:colors",
            ])
            let compact = Self.runFastfetch(arguments: [
                "--logo", "none", "--pipe", "false",
                "-s", "title:os:host:uptime:memory:battery",
            ])
            let logo = Self.runFastfetch(arguments: ["--pipe", "false", "-s", "none"])
            self?.server.update(full: full, compact: compact, logo: logo)
            DispatchQueue.main.async {
                WidgetCenter.shared.reloadAllTimelines()
            }
        }
    }

    private static func runFastfetch(arguments: [String]) -> String {
        let candidates = ["/opt/homebrew/bin/fastfetch", "/usr/local/bin/fastfetch"]
        guard let path = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            return "fastfetch not found. Install it with: brew install fastfetch"
        }

        let langValue = "\(Locale.current.identifier).UTF-8"

        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.environment = [
            "COLORTERM": "truecolor",
            "TERM": "xterm-256color",
            "LANG": langValue,
            "LC_ALL": langValue,
        ]

        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return "Failed to run fastfetch: \(error.localizedDescription)"
        }

        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }
}
