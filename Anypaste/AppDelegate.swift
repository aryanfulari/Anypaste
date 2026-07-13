import AppKit
import QuartzCore

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem?
    private let textCapture = TextCaptureManager()
    private let screenshotCapture = ScreenshotManager()
    private let quickOpen = QuickOpenManager()

    // The two icon states the menu bar button swaps between. The default one is a
    // template image (auto-adapts to light/dark menu bar); the success checkmark is
    // forced to render in solid white via its symbol configuration.
    private let defaultIcon = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "Anypaste")
    private let successIcon = NSImage(systemSymbolName: "checkmark", accessibilityDescription: "Captured")?
        .withSymbolConfiguration(.init(paletteColors: [.white]))

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Belt-and-suspenders alongside the Info.plist "Application is agent (UIElement)"
        // key: keeps Anypaste out of the Dock and the Cmd+Tab switcher.
        NSApp.setActivationPolicy(.accessory)

        setupStatusItem()

        NotificationCenter.default.addObserver(
            self, selector: #selector(refreshMenu),
            name: .anypasteDestinationChanged, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(flashSuccess),
            name: .anypasteCaptureSucceeded, object: nil
        )

        // Accessibility permission is required for everything Anypaste does: watching
        // mouse/keyboard events from other apps, and simulating a Cmd+C keypress.
        if PermissionsManager.ensureAccessibilityAccess(prompt: true) {
            startCapturing()
        } else {
            waitForAccessibilityThenStart()
        }
    }

    // macOS doesn't push a notification when the user flips the Accessibility switch in
    // System Settings, so we just poll for it once a second until it's granted.
    private func waitForAccessibilityThenStart() {
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            if PermissionsManager.ensureAccessibilityAccess(prompt: false) {
                timer.invalidate()
                self.startCapturing()
            }
        }
    }

    private func startCapturing() {
        textCapture.start()
        screenshotCapture.start()
        quickOpen.start()
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = defaultIcon
        item.button?.wantsLayer = true // needed for the crossfade animation in flashSuccess()
        item.menu = buildMenu()
        statusItem = item
    }

    @objc private func refreshMenu() {
        statusItem?.menu = buildMenu()
    }

    /// Morphs the menu bar icon to a white checkmark for one second, then fades back to
    @objc private func flashSuccess() {
        guard let button = statusItem?.button else { return }

        let fadeIn = CATransition()
        fadeIn.type = .fade
        fadeIn.duration = 0.2
        button.layer?.add(fadeIn, forKey: "morphIn")
        button.image = successIcon

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self else { return }
            let fadeOut = CATransition()
            fadeOut.type = .fade
            fadeOut.duration = 0.2
            button.layer?.add(fadeOut, forKey: "morphOut")
            button.image = self.defaultIcon
        }
    }
    private func buildMenu() -> NSMenu {
        let menu = NSMenu()

        let statusLabel = NSMenuItem(
            title: "Appending to: \(DestinationFileManager.shared.currentFileName)",
            action: nil, keyEquivalent: ""
        )
        statusLabel.isEnabled = false
        menu.addItem(statusLabel)
        menu.addItem(.separator())

        // Removed the "n" and "o" key equivalents here:
        menu.addItem(NSMenuItem(title: "New File…", action: #selector(newFile), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Choose File…", action: #selector(chooseFile), keyEquivalent: ""))

        let recents = DestinationFileManager.shared.recentFileURLs
        if !recents.isEmpty {
            let recentsItem = NSMenuItem(title: "Recent Files", action: nil, keyEquivalent: "")
            let submenu = NSMenu()
            for url in recents {
                let recentItem = NSMenuItem(
                    title: url.lastPathComponent, action: #selector(selectRecent(_:)), keyEquivalent: ""
                )
                recentItem.representedObject = url
                recentItem.target = self
                recentItem.state = (url == DestinationFileManager.shared.currentFileURL) ? .on : .off
                submenu.addItem(recentItem)
            }
            recentsItem.submenu = submenu
            menu.addItem(recentsItem)
        }

        menu.addItem(.separator())
        
        // Removed the "q" key equivalent here:
        menu.addItem(NSMenuItem(title: "Quit Anypaste", action: #selector(quit), keyEquivalent: ""))

        for item in menu.items {
            item.target = self
        }
        return menu
    }

    @objc private func selectRecent(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        DestinationFileManager.shared.selectRecentFile(url)
    }

    @objc private func newFile() {
        DestinationFileManager.shared.createNewFile()
    }

    @objc private func chooseFile() {
        DestinationFileManager.shared.chooseExistingFile()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
