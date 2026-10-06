import AppKit
import SwiftUI
import ApplicationServices
import Darwin

final class AppModel: ObservableObject {
    @Published var accessibility = AXIsProcessTrusted()
    @Published var capture = CGPreflightScreenCaptureAccess()
    @Published var status = "Waiting for Accessibility permission"
    let gestures = GestureController()
    private var timer: Timer?
    private var sessionActive = true

    init() {
        gestures.status = { [weak self] message in
            guard let self, self.status != message else { return }
            self.status = message
        }
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.refresh() }
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            self?.gestures.displayConfigurationChanged()
        }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.sessionDidResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.sessionActive = false
            self?.gestures.stop()
            SurfaceBridge.shared.setEnabled(false)
        }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.sessionDidBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.sessionActive = true
            self?.refresh()
        }
        refresh()
    }

    func refresh() {
        accessibility = AXIsProcessTrusted()
        capture = CGPreflightScreenCaptureAccess()
        if Settings.shared.enabled && accessibility && sessionActive {
            gestures.start()
        } else {
            if gestures.running { gestures.stop() }
            status = Settings.shared.enabled ? "Waiting for Accessibility permission" : "Paused"
        }
        SurfaceBridge.shared.setEnabled(gestures.running && Settings.shared.enabled && sessionActive,
                                        leftMove: Settings.shared.leftMove)
    }
    func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        openPrivacy("Privacy_Accessibility")
    }
    func requestCapture() {
        _ = CGRequestScreenCaptureAccess()
        openPrivacy("Privacy_ScreenCapture")
    }
    private func openPrivacy(_ pane: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") { NSWorkspace.shared.open(url) }
    }
}

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var settings = Settings.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 14) {
                Image(systemName: "macwindow.on.rectangle").font(.system(size: 34)).foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Melty Windows").font(.title2.bold())
                    Text(model.status).font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("Enabled", isOn: $settings.enabled).toggleStyle(.switch).labelsHidden()
                    .help("Enable or pause all window gestures")
                    .onChange(of: settings.enabled) { _, _ in model.refresh() }
            }.padding(24)
            Form {
                Section("Permissions") {
                    permission("Accessibility", detail: "Move and resize other apps' windows; handle mouse gestures.",
                               granted: model.accessibility, action: model.requestAccessibility)
                    permission("Screen Recording", detail: "Check a small area around a left click for a solid background.",
                               granted: model.capture, action: model.requestCapture)
                    Text("Pixel samples stay in memory and are discarded after the check. Right-drag resizing needs only Accessibility.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Gestures") {
                    Toggle("Left-drag solid backgrounds to move", isOn: $settings.leftMove)
                    Toggle("Right-drag anywhere to resize", isOn: $settings.rightResize)
                    Toggle("Native live resize (experimental)", isOn: $settings.nativeResize)
                    Text("Uses macOS corner dragging to synchronize content redraws. The original drag stays open during display-edge pushing, with the selected corner fixed for the entire gesture.")
                        .font(.caption).foregroundStyle(.secondary)
                    Toggle("Continue dragging at display edges", isOn: $settings.continueAtEdge)
                    Text("The press location selects the resize corner. The left and top bands use at most 30% of the window; the center resizes bottom/right. At a display edge, continued resizing grows the opposite side.")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("Hold Option before pressing to use an app's own drag. Press Escape during a window gesture to cancel it. Short clicks still reach the app.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("MeltyGUI apps") {
                    Text("Compatible apps connect automatically and keep control of their columns, rows, and window gestures. Their layout can push native window edges to the display boundary while Melty Windows is enabled.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Hyprland settings") {
                    control("Corner band", value: $settings.cornerBand, range: 0...600, suffix: "pt")
                    control("Background radius", value: $settings.radius, range: 1...64, suffix: "pt")
                    control("Color tolerance", value: $settings.tolerance, range: 0...255, suffix: "/ 255")
                    Text("Larger radii avoid more nearby controls. Higher tolerance accepts more shading. Defaults match your saved Hyprland settings: 400, 52, 29.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Excluded apps") {
                    Text("One bundle identifier or exact app name per line. Both gestures pass through. Melty Code Editor and terminals are excluded initially.")
                        .font(.caption).foregroundStyle(.secondary)
                    TextEditor(text: $settings.exclusions).font(.system(.body, design: .monospaced)).frame(height: 72)
                        .accessibilityLabel("Excluded apps")
                }
            }.formStyle(.grouped)
            HStack {
                Button("Test window") { NSApp.sendAction(#selector(AppDelegate.openDemo), to: NSApp.delegate, from: nil) }
                Button("Quit") { NSApp.terminate(nil) }
                Spacer()
                Button("Refresh permissions") { model.refresh() }
            }.padding(.horizontal, 24).padding(.vertical, 14)
        }.frame(minWidth: 520, maxWidth: .infinity, minHeight: 440, maxHeight: .infinity)
    }

    private func permission(_ name: String, detail: String, granted: Bool, action: @escaping () -> Void) -> some View {
        HStack {
            Image(systemName: granted ? "checkmark.circle.fill" : "circle").foregroundStyle(granted ? Color.green : Color.secondary)
            VStack(alignment: .leading, spacing: 3) {
                Text(name)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button(granted ? "Granted" : "Grant access", action: action).disabled(granted)
        }
    }
    private func control(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, suffix: String) -> some View {
        HStack {
            Text(title).frame(width: 135, alignment: .leading)
            Slider(value: value, in: range, step: 1).accessibilityLabel(title)
            Text("\(Int(value.wrappedValue)) \(suffix)").monospacedDigit().frame(width: 76, alignment: .trailing)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let model = AppModel()
    var item: NSStatusItem!
    var window: NSWindow?
    var lastExternalApp: NSRunningApplication?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let mainMenu = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit Melty Windows", action: #selector(quit), keyEquivalent: "q").target = self
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)
        NSApp.mainMenu = mainMenu
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(showSettings),
                                                           name: Notification.Name("org.melty.windows.showSettings"), object: nil)
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "macwindow.on.rectangle", accessibilityDescription: "Melty Windows")
        item.button?.toolTip = "Melty Windows"
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        lastExternalApp = NSWorkspace.shared.frontmostApplication
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            if let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication, app.processIdentifier != getpid() {
                self?.lastExternalApp = app
            }
        }
        showSettings()
    }
    func menuWillOpen(_ menu: NSMenu) {
        menu.removeAllItems()
        let status = menu.addItem(withTitle: model.status, action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(.separator())
        add(menu, Settings.shared.enabled ? "Pause gestures" : "Resume gestures", #selector(toggle))
        add(menu, "Settings…", #selector(showSettings), key: ",")
        if let app = lastExternalApp, let id = app.bundleIdentifier {
            let excluded = Settings.shared.excludedApps.contains(id.lowercased())
            add(menu, "\(excluded ? "Include" : "Exclude") \(app.localizedName ?? id)", #selector(toggleFrontmost))
        }
        add(menu, "Open test window", #selector(openDemo))
        menu.addItem(.separator())
        add(menu, "Quit Melty Windows", #selector(quit), key: "q")
    }
    private func add(_ menu: NSMenu, _ title: String, _ selector: Selector, key: String = "") {
        let item = menu.addItem(withTitle: title, action: selector, keyEquivalent: key)
        item.target = self
    }
    @objc func showSettings() {
        if window == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 590, height: 780),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            window.title = "Melty Windows"
            window.contentMinSize = NSSize(width: 520, height: 440)
            window.contentView = NSHostingView(rootView: SettingsView(model: model))
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    @objc func toggle() { Settings.shared.enabled.toggle(); model.refresh() }
    @objc func toggleFrontmost() {
        guard let id = lastExternalApp?.bundleIdentifier else { return }
        var apps = Settings.shared.excludedApps
        if apps.contains(id.lowercased()) { apps.remove(id.lowercased()) } else { apps.insert(id.lowercased()) }
        Settings.shared.exclusions = apps.sorted().joined(separator: "\n")
    }
    @objc func openDemo() {
        let url = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/Gesture Test.app")
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { [weak self] _, error in
            if let error { DispatchQueue.main.async { self?.model.status = "Could not open the test window: \(error.localizedDescription)" } }
        }
    }
    @objc func quit() { model.gestures.stop(); NSApp.terminate(nil) }
    func applicationWillTerminate(_ notification: Notification) { model.gestures.stop() }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showSettings(); return true }
}

final class DemoDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        window = NSWindow(contentRect: NSRect(x: 300, y: 300, width: 850, height: 560),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "Melty Windows — gesture test"
        window.minSize = NSSize(width: 360, height: 280)
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 850, height: 560))
        content.wantsLayer = true
        content.layer?.backgroundColor = NSColor(calibratedWhite: 0.20, alpha: 1).cgColor
        content.setAccessibilityElement(true)
        content.setAccessibilityRole(.group)
        let label = NSTextField(wrappingLabelWithString: "Drag the empty background to move. Right-drag to resize from the selected corner.\nTry the text field and button: their normal interactions should remain available.")
        label.textColor = .white
        label.frame = NSRect(x: 30, y: 420, width: 640, height: 70)
        label.autoresizingMask = [.minYMargin]
        content.addSubview(label)
        let field = NSTextField(frame: NSRect(x: 30, y: 365, width: 300, height: 28))
        field.stringValue = "Select and edit this text"
        field.autoresizingMask = [.minYMargin]
        content.addSubview(field)
        let button = NSButton(title: "Click to verify normal clicks", target: self, action: #selector(clicked(_:)))
        button.frame = NSRect(x: 350, y: 363, width: 240, height: 32)
        button.autoresizingMask = [.minYMargin]
        content.addSubview(button)
        let menu = NSMenu()
        menu.addItem(withTitle: "Normal right-click reached the test window", action: nil, keyEquivalent: "")
        content.menu = menu
        window.contentView = content
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    @objc func clicked(_ sender: NSButton) { sender.title = "Click received ✓" }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main
enum Main {
    private static var instanceLock: Int32 = -1
    static func main() {
        let app = NSApplication.shared
        if CommandLine.arguments.contains("--diagnostics") {
            print("App bundle: \(Bundle.main.bundleURL.path)")
            print("Bundle identifier: \(Bundle.main.bundleIdentifier ?? "unbundled")")
            print("Accessibility: \(AXIsProcessTrusted())")
            print("Screen capture: \(CGPreflightScreenCaptureAccess())")
            print("Event posting: \(CGPreflightPostEventAccess())")
            print("System cursor: \(NSCursor.currentSystem == nil ? "unavailable" : "available")")
            return
        }
        let demo = CommandLine.arguments.contains("--demo") || Bundle.main.bundleIdentifier == "org.melty.windows.fixture"
        if !demo {
            let directory = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Caches/org.melty.windows")
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            instanceLock = open(directory.appendingPathComponent("instance.lock").path, O_CREAT | O_RDWR | O_CLOEXEC, 0o600)
            guard instanceLock >= 0, flock(instanceLock, LOCK_EX | LOCK_NB) == 0 else {
                DistributedNotificationCenter.default().post(name: Notification.Name("org.melty.windows.showSettings"), object: nil)
                return
            }
        }
        let delegate: NSApplicationDelegate = demo ? DemoDelegate() : AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
